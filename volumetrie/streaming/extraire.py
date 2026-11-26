"""S5 - M2 et M3 : lire la partition taxi en streaming et garder un extrait propre."""
import argparse
import json
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

# on réutilise l'accès fourni dans hf_datasets/acces.py
sys.path.append(str(Path(__file__).resolve().parents[1] / "hf_datasets"))
import acces

DOSSIER = Path(__file__).resolve().parents[1] / "donnees"

# règles de validité
DISTANCE_MAX = 100     # miles
DUREE_MAX = 4 * 3600   # secondes (4 heures)


def verifier(ligne):
    """Renvoie la raison du rejet, ou None si la ligne est bonne."""
    zone = ligne.get("Start_Zone")
    distance = ligne.get("Trip_Distance")
    duree = ligne.get("Trip_Duration")

    if zone is None or distance is None or duree is None:
        return "valeur manquante"
    try:
        zone = int(zone)
        distance = float(distance)
        duree = float(duree)
    except (TypeError, ValueError):
        return "type invalide"

    if distance <= 0:
        return "distance <= 0"
    if distance > DISTANCE_MAX:
        return "distance > 100 miles"
    if duree <= 0:
        return "durée <= 0"
    if duree > DUREE_MAX:
        return "durée > 4 h"
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limite", type=int, default=10000, help="nombre de lignes à parcourir")
    args = parser.parse_args()

    DOSSIER.mkdir(exist_ok=True)
    fichier_extrait = DOSSIER / "extraction.jsonl"
    fichier_bilan = DOSSIER / "bilan_extraction.json"

    parcourues = 0
    retenues = 0
    rejets = Counter()

    flux = iter(acces.ouvrir())
    try:
        with open(fichier_extrait, "w", encoding="utf-8") as sortie:
            for ligne in flux:
                parcourues += 1
                raison = verifier(ligne)
                if raison:
                    rejets[raison] += 1
                else:
                    propre = {
                        "Start_Zone": int(ligne["Start_Zone"]),
                        "Trip_Distance": float(ligne["Trip_Distance"]),
                        "Trip_Duration": float(ligne["Trip_Duration"]),
                    }
                    sortie.write(json.dumps(propre) + "\n")
                    retenues += 1
                if parcourues >= args.limite:
                    break
    finally:
        # on ferme le flux même si il y a une erreur
        flux.close()

    bilan = {
        "date": datetime.now().isoformat(timespec="seconds"),
        "source": acces.SOURCE["repo"],
        "revision": acces.SOURCE["revision"],
        "partition": acces.SOURCE["shard"],
        "colonnes": acces.SOURCE["columns"],
        "limite": args.limite,
        "parcourues": parcourues,
        "retenues": retenues,
        "rejetees": sum(rejets.values()),
        "rejets_par_raison": dict(rejets),
        "regles": [
            "les 3 colonnes sont remplies et numériques",
            "0 < Trip_Distance <= 100 miles",
            "0 < Trip_Duration <= 14400 secondes (4 h)",
        ],
    }
    fichier_bilan.write_text(json.dumps(bilan, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(bilan, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
