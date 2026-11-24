"""Petits tests des règles de validation (sans API). Lancer : python ingestion/tests/test_validation.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))
from validation import motif_rejet  # noqa: E402

PRODUITS = set(range(1, 25))
BONNE = {"offer_id": "O001", "supplier_id": "F01", "product_id": 1, "price_cents": 625,
         "currency": "EUR", "available_units": 2, "observed_on": "2026-11-24"}


def avec(**changements):
    offre = dict(BONNE)
    offre.update(changements)
    return offre


assert motif_rejet(BONNE, PRODUITS, set()) is None
sans_fournisseur = dict(BONNE)
del sans_fournisseur["supplier_id"]
assert motif_rejet(sans_fournisseur, PRODUITS, set()).startswith("champ manquant")
assert motif_rejet(avec(price_cents="inconnu"), PRODUITS, set()).startswith("price_cents")
assert motif_rejet(avec(price_cents=-1), PRODUITS, set()).startswith("prix négatif")
assert motif_rejet(avec(product_id=9999), PRODUITS, set()).startswith("produit inconnu")
assert motif_rejet(avec(currency="USD"), PRODUITS, set()).startswith("devise")
assert motif_rejet(avec(observed_on="24/11/2026"), PRODUITS, set()).startswith("observed_on")
assert motif_rejet(avec(available_units=True), PRODUITS, set()).startswith("available_units")
assert motif_rejet(BONNE, PRODUITS, {"O001"}).startswith("doublon")
print("tests de validation : OK")
