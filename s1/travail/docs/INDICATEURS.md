# M3 · Indicateurs commerciaux

Requêtes : [`sql/indicateurs.sql`](../sql/indicateurs.sql). Sortie complète : [`resultats/02_indicateurs.txt`](resultats/02_indicateurs.txt). Données : schéma `metier` après import (rejets exclus). Période des commandes : 1er septembre au 19 novembre 2026.

## Résultats

| Indicateur | Valeur | Définition |
| --- | --- | --- |
| Commandes | 400 | lignes de `metier.orders` |
| dont terminées (`completed`) | 320 (80 %) | |
| dont en attente (`pending`) | 40 (10 %) | |
| dont annulées (`cancelled`) | 40 (10 %) | |
| Clients | 180 | |
| Clients sans commande | **30** (identifiants 151 à 180) | aucun enregistrement dans `orders`, tous statuts confondus |
| Clients sans commande terminée | 60 | |
| Montant des lignes des commandes terminées (CA) | **26 210,00 €** (2 621 000 centimes) | Σ `quantity × unit_price_cents` des lignes dont la commande est `completed` |
| Panier moyen | **81,91 €** | CA ÷ **320** commandes terminées ayant au moins une ligne |

Répartition mensuelle (date de commande) : septembre 9 717,50 € (120 commandes terminées), octobre 10 261,25 € (124), novembre jusqu'au 19 : 6 231,25 € (76).

## Rapprochement commandé / payé (grain commande)

| Statut | Commandes | Paiements | Commandé | Capturé | En attente | Reste à capturer |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| completed | 320 | 360 | 26 210,00 € | 26 210,00 € | 0,00 € | 0,00 € |
| pending | 40 | 40 | 3 223,75 € | 0,00 € | 3 223,75 € | 3 223,75 € |
| cancelled | 40 | 80 | 3 283,75 € | 3 283,75 € | 0,00 € | 0,00 € |
| **Total** | **400** | **480** | **32 717,50 €** | **29 493,75 €** | **3 223,75 €** | **3 223,75 €** |

Lecture : chaque commande terminée est intégralement capturée, chaque commande en attente a un paiement en attente du montant exact, et chaque commande annulée est, elle aussi, intégralement capturée (anomalie 6 de [ANOMALIES.md](ANOMALIES.md)). Aucune commande ne présente d'écart entre le commandé et la somme capturé + en attente.

## Hypothèses

1. **Le CA est le montant des lignes des commandes terminées**, valorisé au prix de la transaction (`unit_price_cents`), pas au prix catalogue. Les commandes en attente ne sont pas encore acquises ; les annulées ne le seront pas.
2. **Le CA est rattaché à la date de commande** (`ordered_on`), pas à la date de paiement. Dans ces données les deux coïncident.
3. **Le dénominateur du panier moyen** est le nombre de commandes terminées ayant au moins une ligne d'article. Une commande vide ne représente pas d'achat ; le cas ne se présente pas ici (contrôle C7), donc le dénominateur vaut 320.
4. **Les lignes rejetées** (doublon et orpheline) ne sont pas dans le CA : le doublon aurait compté deux fois le même achat, l'orpheline n'a pas de statut.
5. **Le rapprochement se fait au grain commande** : lignes et paiements sont agrégés séparément avant d'être joints.
6. Les paiements capturés sur commandes annulées sont présumés remboursés hors des sources ; ils ne sont pas déduits du CA, qui ne les contient pas.

## Vérifications de cohérence

| Vérification | Attendu | Observé |
| --- | --- | --- |
| Somme des commandes par statut = nombre de commandes | 400 | 400 |
| CA via la vue `v_commande_montant` = CA calculé directement sur `order_items ⋈ orders` | égal | 2 621 000 = 2 621 000 centimes |
| Total des lignes via la vue = total de la table `order_items` (C3) | égal | 3 271 750 = 3 271 750 |
| Total des paiements via `v_rapprochement` = total de `payments` (C4) | égal | 3 271 750 = 3 271 750 |
| Une ligne de rapprochement par commande (C5) | 400 | 400 |
| Capturé des commandes terminées = CA | égal | 26 210,00 € = 26 210,00 € |
| Recalcul indépendant en Python depuis les fichiers bruts (doublon et orphelin écartés) | mêmes valeurs | CA 2 621 000, panier 81,906 €, 30 clients sans commande, 0 écart de rapprochement |
