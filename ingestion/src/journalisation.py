"""Journal de la collecte et écriture des fichiers de sortie."""
import json
import logging


def creer_logger(chemin_log):
    """Écrit les messages à l'écran et dans un fichier .log."""
    logger = logging.getLogger("collecteur")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    format_ligne = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    for handler in (logging.StreamHandler(), logging.FileHandler(chemin_log, encoding="utf-8")):
        handler.setFormatter(format_ligne)
        logger.addHandler(handler)
    return logger


def ecrire_jsonl(chemin, lignes):
    """Un objet JSON par ligne, en UTF-8."""
    with open(chemin, "w", encoding="utf-8") as fichier:
        for ligne in lignes:
            fichier.write(json.dumps(ligne, ensure_ascii=False) + "\n")


def ecrire_bilan(chemin, bilan):
    with open(chemin, "w", encoding="utf-8") as fichier:
        json.dump(bilan, fichier, ensure_ascii=False, indent=2)
