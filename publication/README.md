---
pretty_name: NovaMarket S5 - trajets de taxi synthétiques
tags:
  - education
---

# NovaMarket S5 - trajets de taxi synthétiques

Jeu de données d'exercice pour la séance S5 du cours « Ingénierie des données et pipelines SQL ».

Le but est de s'entraîner à publier un jeu de données sur le Hub et à gérer deux révisions.

Les données sont **synthétiques** (inventées) : elles viennent du fichier `secours/trajets_fictifs.jsonl` du kit du cours. Elles ont le même schéma que la partition Yellow de janvier 2024 du dépôt `DinoPonjevic/NYC_TaxiData` (révision `5941adbf8c0b9930e47002dc3103de3f9291360d`), mais aucune ligne réelle n'est republiée ici, car la licence de ce miroir est `unknown`.

Usage : exercice pédagogique uniquement. Les chiffres ne représentent pas de vrais trajets.

## Colonnes et unités

Grain : une ligne = un trajet.

| Colonne | Type | Unité | Description |
|---|---|---|---|
| `Start_Zone` | entier | code zone TLC (1 à 265) | zone de départ |
| `Trip_Distance` | décimal | miles | distance du trajet |
| `Trip_Duration` | entier | secondes | durée du trajet |

Pas de date dans ce jeu. Pas de valeur manquante.

## Extraction et qualité

- Fichier : `trajets_synthetiques.jsonl`, 4 lignes.
- Lignes parcourues : 6 (fichier `secours/trajets_fictifs.jsonl` du kit). Gardées : 4. Rejetées : 2.
- Règles appliquées (les mêmes que dans notre pipeline S5) :
  - 0 < `Trip_Distance` <= 100 miles et 0 < `Trip_Duration` <= 14 400 secondes ;
  - `Start_Zone` doit exister dans la table des zones TLC (codes 1 à 265).
- Lignes rejetées : une distance négative (-2.0) et une zone `999` qui n'existe pas.
- Limite : 4 lignes inventées, donc rien de représentatif.
- Reproduction : `grep -v -e '"Trip_Distance":-2.0' -e '"Start_Zone":999' volumetrie/secours/trajets_fictifs.jsonl > publication/trajets_synthetiques.jsonl`

## Révisions

- Révision initiale (v1, commit `0bb7db6950a40499991e856330c9eb7efcf420a6`) : les 6 lignes du fichier synthétique, sans filtre.
- Deuxième révision (v2) : on applique les règles de qualité. On enlève la ligne avec une distance négative et la ligne avec la zone `999`, parce qu'elles fausseraient les moyennes et ne peuvent pas être reliées à une zone. Le fichier passe de 6 à 4 lignes. Le schéma ne change pas.
