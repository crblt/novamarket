"""Contrôle des offres reçues de l'API fournisseur."""
import csv
from datetime import date

CHAMPS = ["offer_id", "supplier_id", "product_id", "price_cents",
          "currency", "available_units", "observed_on"]


def lire_produits(chemin):
    """Renvoie l'ensemble des product_id du catalogue S2."""
    with open(chemin, encoding="utf-8") as fichier:
        return {int(ligne["product_id"]) for ligne in csv.DictReader(fichier)}


def est_entier(valeur):
    # En Python, True et False sont aussi des int : on les exclut
    return isinstance(valeur, int) and not isinstance(valeur, bool)


def est_date_iso(valeur):
    if not isinstance(valeur, str) or len(valeur) != 10:
        return False
    try:
        date.fromisoformat(valeur)
        return True
    except ValueError:
        return False


def motif_rejet(offre, produits, offres_deja_vues):
    """Renvoie None si l'offre est valide, sinon le motif du rejet (le premier trouvé)."""
    if not isinstance(offre, dict):
        return "offre qui n'est pas un objet JSON"

    manquants = [champ for champ in CHAMPS if offre.get(champ) is None]
    if manquants:
        return "champ manquant : " + ", ".join(manquants)

    if not isinstance(offre["offer_id"], str) or offre["offer_id"] == "":
        return "offer_id invalide"
    if not isinstance(offre["supplier_id"], str) or offre["supplier_id"] == "":
        return "supplier_id invalide"
    if not est_entier(offre["product_id"]):
        return f"product_id n'est pas un entier : {offre['product_id']!r}"
    if not est_entier(offre["price_cents"]):
        return f"price_cents n'est pas un entier : {offre['price_cents']!r}"
    if offre["price_cents"] < 0:
        return f"prix négatif : {offre['price_cents']}"
    if not est_entier(offre["available_units"]) or offre["available_units"] < 0:
        return f"available_units invalide : {offre['available_units']!r}"
    if offre["currency"] != "EUR":
        return f"devise différente de EUR : {offre['currency']!r}"
    if not est_date_iso(offre["observed_on"]):
        return f"observed_on n'est pas une date AAAA-MM-JJ : {offre['observed_on']!r}"
    if offre["product_id"] not in produits:
        return f"produit inconnu du catalogue : {offre['product_id']}"
    if offre["offer_id"] in offres_deja_vues:
        return f"doublon : {offre['offer_id']} déjà reçu"
    return None
