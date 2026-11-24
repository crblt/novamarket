"""Collecte des offres fournisseurs : asynchrone, concurrence bornée, reprises limitées.

Exemples (depuis novamarket/, venv activé) :
    python ingestion/src/collecteur.py --scenario clean --run clean01
    python ingestion/src/collecteur.py --scenario atelier --run atelier01
    python ingestion/src/collecteur.py --scenario clean --run seq01 --sequentiel
"""
import argparse
import asyncio
import json
import os
import sys
import time
from collections import Counter
from pathlib import Path

import aiohttp

from journalisation import creer_logger, ecrire_bilan, ecrire_jsonl
from validation import CHAMPS, lire_produits, motif_rejet

DOSSIER = Path(__file__).resolve().parent.parent          # ingestion/
DATA = DOSSIER / "data"
LOGS = DOSSIER / "logs"
PRODUITS = DOSSIER.parent / "s2" / "donnees" / "products.csv"
URL = f"http://127.0.0.1:{os.environ.get('NOVAMARKET_API_PORT', '18080')}/offers"

MAX_TENTATIVES = 3      # par page
TIMEOUT = 1.0           # secondes par requête
ATTENTE_MAX = 5         # on n'attend jamais plus, même si Retry-After demande plus
STATUTS_TRANSITOIRES = {429, 500, 502, 503, 504}


class ErreurTransitoire(Exception):
    """Erreur qui peut passer si on réessaie (429, 503, timeout, JSON cassé...)."""
    def __init__(self, message, attente=None):
        super().__init__(message)
        self.attente = attente


class ErreurPermanente(Exception):
    """Erreur qui ne passera pas en réessayant (400, 404...)."""


async def appel(session, page, scenario, run, tentative, bruts):
    """Un seul appel HTTP. La réponse brute est toujours gardée dans `bruts`."""
    params = {"page": page, "scenario": scenario, "run": run}
    try:
        async with session.get(URL, params=params) as reponse:
            texte = await reponse.text()
            bruts.append({"page": page, "tentative": tentative,
                          "statut": reponse.status, "corps": texte})
            if reponse.status in STATUTS_TRANSITOIRES:
                retry_after = reponse.headers.get("Retry-After", "")
                attente = float(retry_after) if retry_after.isdigit() else None
                raise ErreurTransitoire(f"HTTP {reponse.status}", attente)
            if reponse.status != 200:
                raise ErreurPermanente(f"HTTP {reponse.status}")
    except asyncio.TimeoutError:
        bruts.append({"page": page, "tentative": tentative, "statut": None,
                      "corps": None, "erreur": "timeout"})
        raise ErreurTransitoire(f"timeout (plus de {TIMEOUT} s)")
    except aiohttp.ClientError as erreur:
        bruts.append({"page": page, "tentative": tentative, "statut": None,
                      "corps": None, "erreur": str(erreur)})
        raise ErreurTransitoire(f"erreur réseau : {erreur}")

    # HTTP 200 ne veut pas dire que le contenu est bon
    try:
        donnees = json.loads(texte)
    except json.JSONDecodeError:
        raise ErreurTransitoire("JSON invalide")
    if not isinstance(donnees, dict) or not isinstance(donnees.get("items"), list):
        raise ErreurTransitoire("réponse sans liste items")
    return donnees


async def lire_page(session, limite, page, scenario, run, bruts, compteurs, logger):
    """Lit une page avec au plus MAX_TENTATIVES essais."""
    for tentative in range(1, MAX_TENTATIVES + 1):
        compteurs["requetes_http"] += 1
        try:
            async with limite:  # au plus N appels en même temps
                compteurs["en_cours"] += 1
                compteurs["max_simultanes"] = max(compteurs["max_simultanes"], compteurs["en_cours"])
                try:
                    donnees = await appel(session, page, scenario, run, tentative, bruts)
                finally:
                    compteurs["en_cours"] -= 1
            logger.info("page %s reçue (tentative %s, %s offres)", page, tentative, len(donnees["items"]))
            return donnees
        except ErreurTransitoire as erreur:
            if tentative == MAX_TENTATIVES:
                logger.error("page %s abandonnée après %s tentatives : %s", page, tentative, erreur)
                raise
            # Retry-After si l'API le donne, sinon 0,5 s puis 1 s
            attente = erreur.attente if erreur.attente is not None else 0.5 * 2 ** (tentative - 1)
            attente = min(attente, ATTENTE_MAX)
            compteurs["reprises"] += 1
            logger.warning("page %s tentative %s : %s, nouvel essai dans %.1f s",
                           page, tentative, erreur, attente)
            await asyncio.sleep(attente)  # en dehors du sémaphore : on ne bloque pas les autres pages
        except ErreurPermanente as erreur:
            logger.error("page %s : erreur permanente %s, pas de nouvel essai", page, erreur)
            raise


async def collecter(scenario, run, concurrence, bruts, compteurs, logger):
    """Renvoie {numero_page: réponse}, le nombre total de pages et la liste des erreurs."""
    limite = asyncio.Semaphore(concurrence)
    timeout = aiohttp.ClientTimeout(total=TIMEOUT)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        # La page 1 donne total_pages, ensuite on lance les autres en parallèle (bornées)
        premiere = await lire_page(session, limite, 1, scenario, run, bruts, compteurs, logger)
        total = premiere["total_pages"]
        numeros = list(range(2, total + 1))
        resultats = await asyncio.gather(
            *(lire_page(session, limite, p, scenario, run, bruts, compteurs, logger) for p in numeros),
            return_exceptions=True,
        )
    pages = {1: premiere}
    erreurs = []
    for numero, resultat in zip(numeros, resultats):
        if isinstance(resultat, Exception):
            erreurs.append(f"page {numero} : {resultat}")
        else:
            pages[numero] = resultat
    return pages, total, erreurs


def verifier_completude(pages, total, erreurs):
    """Le lot n'est publié que si toutes les pages sont là et cohérentes."""
    if erreurs:
        return erreurs
    problemes = []
    for numero in range(1, total + 1):
        if numero not in pages:
            problemes.append(f"page {numero} manquante")
        elif pages[numero].get("page") != numero:
            problemes.append(f"page {numero} : numéro reçu {pages[numero].get('page')}")
    if pages.get(total, {}).get("next_page") is not None:
        problemes.append("la dernière page a encore un next_page")
    return problemes


def main():
    parser = argparse.ArgumentParser(description="Collecte des offres fournisseurs")
    parser.add_argument("--scenario", default="atelier", choices=["clean", "atelier", "panne"])
    parser.add_argument("--run", default="essai-" + time.strftime("%H%M%S"),
                        help="nom de l'essai (lettres, chiffres, - et _)")
    parser.add_argument("--concurrence", type=int, default=3, help="appels HTTP simultanés maximum")
    parser.add_argument("--sequentiel", action="store_true", help="une page à la fois (comparaison)")
    args = parser.parse_args()
    concurrence = 1 if args.sequentiel else args.concurrence

    for dossier in (DATA / "raw", DATA / "valid", DATA / "rejected", LOGS):
        dossier.mkdir(parents=True, exist_ok=True)
    nom = f"{args.scenario}_{args.run}"
    logger = creer_logger(LOGS / f"{nom}.log")
    logger.info("début : scénario %s, run %s, concurrence %s", args.scenario, args.run, concurrence)

    produits = lire_produits(PRODUITS)
    bruts = []
    compteurs = {"requetes_http": 0, "reprises": 0, "en_cours": 0, "max_simultanes": 0}
    debut = time.perf_counter()
    try:
        pages, total, erreurs = asyncio.run(
            collecter(args.scenario, args.run, concurrence, bruts, compteurs, logger))
    except (ErreurTransitoire, ErreurPermanente) as erreur:
        pages, total, erreurs = {}, None, [f"page 1 : {erreur}"]
    duree = round(time.perf_counter() - debut, 3)

    # raw : tout ce qui a été reçu, y compris les essais ratés
    ecrire_jsonl(DATA / "raw" / f"{nom}.jsonl", bruts)

    # Validation, page par page et dans l'ordre, pour que le doublon gardé soit toujours le même
    valides, rejets, deja_vues = [], [], set()
    for numero in sorted(pages):
        for position, offre in enumerate(pages[numero]["items"], start=1):
            motif = motif_rejet(offre, produits, deja_vues)
            if motif is None:
                deja_vues.add(offre["offer_id"])
                valides.append({champ: offre[champ] for champ in CHAMPS})
            else:
                rejets.append({"page": numero, "position": position, "motif": motif, "offre": offre})
                logger.warning("offre rejetée page %s position %s : %s", numero, position, motif)

    problemes = verifier_completude(pages, total, erreurs) if total else erreurs
    statut = "succes" if not problemes else "echec"
    if statut == "succes":
        ecrire_jsonl(DATA / "valid" / "offres.jsonl", valides)
        ecrire_jsonl(DATA / "rejected" / f"{nom}.jsonl", rejets)
    else:
        logger.error("lot incomplet : %s", " ; ".join(problemes))
        logger.error("rien n'est publié dans valid/ (l'ancien offres.jsonl n'est pas modifié)")

    bilan = {
        "scenario": args.scenario,
        "run": args.run,
        "statut": statut,
        "concurrence_max": concurrence,
        "appels_simultanes_observes": compteurs["max_simultanes"],
        "pages_attendues": total,
        "pages_recues": len(pages),
        "requetes_http": compteurs["requetes_http"],
        "reprises": compteurs["reprises"],
        "offres_vues": len(valides) + len(rejets),
        "offres_valides": len(valides) if statut == "succes" else 0,
        "offres_rejetees": len(rejets) if statut == "succes" else 0,
        "motifs_rejet": dict(Counter(r["motif"].split(" :")[0] for r in rejets)) if statut == "succes" else {},
        "problemes": problemes,
        "duree_secondes": duree,
    }
    ecrire_bilan(LOGS / f"{nom}_bilan.json", bilan)
    logger.info("bilan : %s", json.dumps(bilan, ensure_ascii=False))
    return 0 if statut == "succes" else 1


if __name__ == "__main__":
    sys.exit(main())
