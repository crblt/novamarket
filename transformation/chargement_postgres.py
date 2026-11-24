"""Chargement des offres valides (S3) dans PostgreSQL, en une seule transaction.

Exemples (depuis novamarket/, venv activé, NOVAMARKET_DSN et PGPASSWORD définis) :
    python transformation/chargement_postgres.py
    python transformation/chargement_postgres.py --fichier transformation/secours/offres.jsonl
    python transformation/chargement_postgres.py --simuler-panne 5
"""
import argparse
import json
import os
import sys
from collections import Counter
from datetime import date, datetime
from pathlib import Path

import psycopg

DOSSIER = Path(__file__).resolve().parent.parent          # novamarket/
FICHIER_DEFAUT = DOSSIER / "ingestion" / "data" / "valid" / "offres.jsonl"

CREATION = """
CREATE SCHEMA IF NOT EXISTS fournisseur;

-- Référentiel des fournisseurs connus (liste du contrat de l'API, voir ingestion/CONTRAT.md)
CREATE TABLE IF NOT EXISTS fournisseur.fournisseurs (
    supplier_id text PRIMARY KEY
);
INSERT INTO fournisseur.fournisseurs VALUES ('F01'), ('F02'), ('F03') ON CONFLICT DO NOTHING;

-- Une ligne = une offre observée à une date. La clé permet plusieurs dates pour une même offre.
CREATE TABLE IF NOT EXISTS fournisseur.offres (
    offer_id text NOT NULL,
    observed_on date NOT NULL,
    supplier_id text NOT NULL REFERENCES fournisseur.fournisseurs(supplier_id),
    product_id integer NOT NULL REFERENCES metier.products(product_id),
    price_cents integer NOT NULL CHECK (price_cents >= 0),
    currency text NOT NULL CHECK (currency = 'EUR'),
    available_units integer NOT NULL CHECK (available_units >= 0),
    lot_id text NOT NULL,
    PRIMARY KEY (offer_id, observed_on)
);

-- Une ligne = un lancement du chargement (réussi ou non)
CREATE TABLE IF NOT EXISTS fournisseur.lots (
    lot_id text PRIMARY KEY,
    fichier text NOT NULL,
    lance_le timestamptz NOT NULL DEFAULT now(),
    statut text NOT NULL,
    lues integer NOT NULL,
    inserees integer NOT NULL,
    mises_a_jour integer NOT NULL,
    inchangees integer NOT NULL,
    rejetees integer NOT NULL,
    message text
);

-- Une ligne = une ligne du fichier refusée, avec la cause
CREATE TABLE IF NOT EXISTS fournisseur.rejets (
    lot_id text NOT NULL,
    ligne integer NOT NULL,
    motif text NOT NULL,
    contenu text NOT NULL
);
"""

UPSERT = """
INSERT INTO fournisseur.offres
    (offer_id, observed_on, supplier_id, product_id, price_cents, currency, available_units, lot_id)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT (offer_id, observed_on) DO UPDATE
SET supplier_id = excluded.supplier_id,
    product_id = excluded.product_id,
    price_cents = excluded.price_cents,
    currency = excluded.currency,
    available_units = excluded.available_units,
    lot_id = excluded.lot_id
WHERE (fournisseur.offres.supplier_id, fournisseur.offres.product_id, fournisseur.offres.price_cents,
       fournisseur.offres.currency, fournisseur.offres.available_units)
      IS DISTINCT FROM
      (excluded.supplier_id, excluded.product_id, excluded.price_cents,
       excluded.currency, excluded.available_units)
"""


def est_entier(valeur):
    return isinstance(valeur, int) and not isinstance(valeur, bool)


def controler(texte, produits, fournisseurs, deja_vues):
    """Renvoie (offre convertie, None) si la ligne est bonne, sinon (None, motif)."""
    try:
        offre = json.loads(texte)
    except json.JSONDecodeError:
        return None, "JSON invalide"
    if not isinstance(offre, dict):
        return None, "la ligne n'est pas un objet JSON"
    for champ in ["offer_id", "observed_on", "supplier_id", "product_id",
                  "price_cents", "currency", "available_units"]:
        if offre.get(champ) is None:
            return None, f"champ manquant : {champ}"
    if not est_entier(offre["product_id"]) or not est_entier(offre["price_cents"]):
        return None, "product_id ou price_cents n'est pas un entier"
    if not est_entier(offre["available_units"]) or offre["available_units"] < 0:
        return None, f"unités invalides : {offre['available_units']!r}"
    if offre["price_cents"] < 0:
        return None, f"prix négatif : {offre['price_cents']}"
    if offre["currency"] != "EUR":
        return None, f"devise différente de EUR : {offre['currency']!r}"
    try:
        jour = date.fromisoformat(offre["observed_on"])
    except (TypeError, ValueError):
        return None, f"date invalide : {offre['observed_on']!r}"
    if offre["supplier_id"] not in fournisseurs:
        return None, f"fournisseur inconnu : {offre['supplier_id']!r}"
    if offre["product_id"] not in produits:
        return None, f"produit inconnu du catalogue : {offre['product_id']}"
    cle = (offre["offer_id"], jour)
    if cle in deja_vues:
        return None, f"doublon dans le fichier : {offre['offer_id']} le {jour}"
    deja_vues.add(cle)
    return (offre["offer_id"], jour, offre["supplier_id"], offre["product_id"],
            offre["price_cents"], offre["currency"], offre["available_units"]), None


def main():
    parser = argparse.ArgumentParser(description="Chargement des offres fournisseurs dans PostgreSQL")
    parser.add_argument("--fichier", default=str(FICHIER_DEFAUT))
    parser.add_argument("--simuler-panne", type=int, default=0,
                        help="provoque une erreur après N lignes écrites (pour tester le ROLLBACK)")
    args = parser.parse_args()

    if "NOVAMARKET_DSN" not in os.environ:
        sys.exit("NOVAMARKET_DSN n'est pas défini (voir transformation/RAPPORT.md)")

    lot_id = "lot-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    lignes = Path(args.fichier).read_text(encoding="utf-8").splitlines()
    compteurs = Counter()
    motifs = Counter()

    with psycopg.connect(os.environ["NOVAMARKET_DSN"], connect_timeout=5) as connexion:
        connexion.execute(CREATION)
        connexion.commit()
        produits = {ligne[0] for ligne in connexion.execute("SELECT product_id FROM metier.products")}
        fournisseurs = {ligne[0] for ligne in connexion.execute("SELECT supplier_id FROM fournisseur.fournisseurs")}

        try:
            # Tout le lot dans une transaction : soit tout est écrit, soit rien.
            with connexion.transaction():
                deja_vues = set()
                for numero, texte in enumerate(lignes, start=1):
                    if not texte.strip():
                        continue
                    compteurs["lues"] += 1
                    valeurs, motif = controler(texte, produits, fournisseurs, deja_vues)
                    if motif:
                        compteurs["rejetees"] += 1
                        motifs[motif.split(" :")[0]] += 1
                        connexion.execute(
                            "INSERT INTO fournisseur.rejets VALUES (%s, %s, %s, %s)",
                            (lot_id, numero, motif, texte))
                        continue
                    existait = connexion.execute(
                        "SELECT 1 FROM fournisseur.offres WHERE offer_id = %s AND observed_on = %s",
                        valeurs[:2]).fetchone() is not None
                    changees = connexion.execute(UPSERT, valeurs + (lot_id,)).rowcount
                    if changees == 0:
                        compteurs["inchangees"] += 1
                    elif existait:
                        compteurs["mises_a_jour"] += 1
                    else:
                        compteurs["inserees"] += 1
                    if args.simuler_panne and compteurs["inserees"] + compteurs["mises_a_jour"] >= args.simuler_panne:
                        raise RuntimeError(f"panne simulée après {args.simuler_panne} lignes écrites")
                connexion.execute(
                    "INSERT INTO fournisseur.lots (lot_id, fichier, statut, lues, inserees, mises_a_jour,"
                    " inchangees, rejetees) VALUES (%s, %s, 'succes', %s, %s, %s, %s, %s)",
                    (lot_id, args.fichier, compteurs["lues"], compteurs["inserees"],
                     compteurs["mises_a_jour"], compteurs["inchangees"], compteurs["rejetees"]))
            statut = "succes"
        except Exception as erreur:
            # La transaction a été annulée (ROLLBACK) : aucune offre de ce lot n'est restée.
            statut = "echec"
            with connexion.transaction():
                connexion.execute(
                    "INSERT INTO fournisseur.lots (lot_id, fichier, statut, lues, inserees, mises_a_jour,"
                    " inchangees, rejetees, message) VALUES (%s, %s, 'echec', %s, 0, 0, 0, 0, %s)",
                    (lot_id, args.fichier, compteurs["lues"], str(erreur)))
            print(f"ERREUR : {erreur} -> ROLLBACK, rien n'a été écrit pour ce lot")

        total = connexion.execute("SELECT COUNT(*) FROM fournisseur.offres").fetchone()[0]

    bilan = {"lot_id": lot_id, "statut": statut, "fichier": args.fichier,
             "lues": compteurs["lues"], "inserees": compteurs["inserees"] if statut == "succes" else 0,
             "mises_a_jour": compteurs["mises_a_jour"] if statut == "succes" else 0,
             "inchangees (ignorées)": compteurs["inchangees"] if statut == "succes" else 0,
             "rejetees": compteurs["rejetees"] if statut == "succes" else 0,
             "motifs_rejet": dict(motifs) if statut == "succes" else {},
             "offres_en_base": total}
    print(json.dumps(bilan, ensure_ascii=False, indent=2))
    return 0 if statut == "succes" else 1


if __name__ == "__main__":
    sys.exit(main())
