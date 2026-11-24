# Contrat de l'API fournisseur (M1)

URL de base : `http://127.0.0.1:18080`

| Route | Réponse |
| --- | --- |
| `GET /health` | `{"status": "ok"}` |
| `GET /offers?page=1&scenario=clean&run=essai01` | une page d'offres |

Paramètres de `/offers` :
- `page` : de 1 à 6 (en dehors : HTTP 400) ;
- `scenario` : `clean`, `atelier` ou `panne` ;
- `run` : nom de l'essai. Avec un nouveau `run`, les erreurs de la première tentative reviennent.

## Pagination

Chaque réponse contient `page`, `total_pages`, `next_page` et `items`. Il y a 6 pages de 4 offres, soit 24 offres.

- `next_page` vaut le numéro de la page suivante, et `null` sur la dernière page.
- **Condition d'arrêt** : on s'arrête quand `next_page` est `null`. En pratique, je lis la page 1, je récupère `total_pages`, puis je demande les pages 2 à `total_pages` en parallèle.
- La collecte est complète seulement si j'ai bien les 6 pages, chacune avec le bon numéro, et si la dernière a `next_page = null`.

Exemple de réponse (scénario clean, page 1, raccourci à 2 offres sur 4, données fictives) :

```json
{
  "page": 1,
  "total_pages": 6,
  "next_page": 2,
  "items": [
    {"offer_id": "O001", "supplier_id": "F01", "product_id": 1, "price_cents": 625,
     "currency": "EUR", "available_units": 2, "observed_on": "2026-11-24"},
    {"offer_id": "O002", "supplier_id": "F02", "product_id": 2, "price_cents": 750,
     "currency": "EUR", "available_units": 4, "observed_on": "2026-11-24"}
  ]
}
```

## Champs d'une offre

| Champ | Type | Règle |
| --- | --- | --- |
| offer_id | texte | obligatoire, **clé métier** (une offre = un offer_id) |
| supplier_id | texte | obligatoire (F01, F02, F03) |
| product_id | entier | doit exister dans le catalogue S2 (`s2/donnees/products.csv`, produits 1 à 24) |
| price_cents | entier | ≥ 0, en centimes |
| currency | texte | `EUR` |
| available_units | entier | ≥ 0 |
| observed_on | texte | date `AAAA-MM-JJ` |

## Comparaison des scénarios

| Scénario | Ce que j'ai observé |
| --- | --- |
| clean | les 6 pages répondent du premier coup, 24 offres toutes correctes |
| atelier | 1er essai : page 2 → HTTP 429 avec `Retry-After: 1` ; page 3 → HTTP 200 mais JSON cassé ; page 4 → réponse trop lente (timeout). Au 2e essai, tout passe. Mais 4 offres sont fausses alors que le HTTP est 200 : supplier_id manquant (page 2), prix « inconnu » (page 3), produit 9999 (page 5), O001 en double (page 6) |
| panne | la page 6 répond toujours HTTP 503 |

**Un HTTP 200 ne garantit pas une bonne donnée** : la page 3 renvoie 200 avec un JSON illisible, et des pages en 200 contiennent des offres non conformes. C'est pour ça que je contrôle le transport (statut, JSON) et le contenu (chaque offre) séparément.
