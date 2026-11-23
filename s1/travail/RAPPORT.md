# Rapport S1 – NovaMarket

## M1 – Sources et schéma

### Grain des fichiers

| Fichier | Une ligne = | Clé |
| --- | --- | --- |
| customers.csv | un client | customer_id |
| orders.csv | une commande | order_id |
| order_items.csv | un article d'une commande | order_item_id |
| payments.ndjson | un paiement | payment_id |

Relations :
- un client peut avoir plusieurs commandes (1–N)
- une commande peut avoir plusieurs lignes d'articles (1–N)
- une commande peut avoir plusieurs paiements (1–N)

Les lignes d'articles et les paiements n'ont pas de lien direct entre eux : les deux sont rattachés à la commande.

### Schéma

```
customers                orders                      order_items
-----------              ---------------             -------------------
customer_id  PK  <---    order_id     PK   <---      order_item_id     PK
customer_name            customer_id  FK             order_id          FK
city                     ordered_on                  product_id
                         status (completed,          quantity          (> 0)
                                 pending,            unit_price_cents  (>= 0)
                                 cancelled)
                                           <---      payments
                                                     -------------------
                                                     payment_id        PK
                                                     order_id          FK
                                                     paid_on
                                                     amount_cents      (> 0)
                                                     status (captured, pending)
```

Types : `integer` pour les identifiants et les montants (en centimes), `date` pour les dates, `text` pour le reste.

Ordre d'import : customers, puis orders, puis order_items et payments (il faut que le parent existe avant l'enfant à cause des clés étrangères).

### Mes deux choix

**1. Une table de réception sans clé avant les tables métier.**
Si j'importe directement dans les tables avec les clés, le `\copy` plante dès qu'il y a un doublon ou une commande inexistante, et je ne vois pas les lignes à problème. Avec la réception sans clé, tout le fichier est chargé. Je peux ensuite chercher les problèmes, les noter dans `reception.rejets`, et n'envoyer que les bonnes lignes dans `metier`.

**2. Les montants restent en centimes (integer).**
Les fichiers sont en centimes. En les gardant en entiers, il n'y a pas d'erreur d'arrondi. Je divise par 100 seulement à l'affichage.

## M2 – Import

| Fichier | Reçues | Intégrées | Rejetées |
| --- | --- | --- | --- |
| customers.csv | 180 | 180 | 0 |
| orders.csv | 400 | 400 | 0 |
| order_items.csv | 802 | 800 | 2 |
| payments.ndjson | 480 | 480 | 0 |

Journal des rejets (`reception.rejets`) :

| Fichier | Identifiant | Raison |
| --- | --- | --- |
| order_items.csv | 7 | doublon exact (la ligne apparaît 2 fois) |
| order_items.csv | 801 | commande inexistante : 9999 |

## M3 – Indicateurs

| Indicateur | Résultat |
| --- | --- |
| Commandes terminées (completed) | 320 |
| Commandes en attente (pending) | 40 |
| Commandes annulées (cancelled) | 40 |
| Clients sans commande | 30 (sur 180) |
| CA des commandes terminées | 26 210,00 € |
| Panier moyen | 81,91 € |

**Hypothèses**
- Le CA = somme de `quantity × unit_price_cents` des lignes des commandes `completed` uniquement.
- Panier moyen = CA / nombre de commandes terminées (320). Je divise par les commandes et pas par les lignes, sinon j'aurais le prix moyen d'une ligne (40,95 €).
- Les 2 lignes rejetées ne sont pas comptées.

**Rapprochement avec les paiements** (total par commande d'abord, puis jointure) :

| Statut | Commandes | Montant commandé | Encaissé | En attente |
| --- | --- | --- | --- | --- |
| completed | 320 | 26 210,00 € | 26 210,00 € | 0,00 € |
| pending | 40 | 3 223,75 € | 0,00 € | 3 223,75 € |
| cancelled | 40 | 3 283,75 € | 3 283,75 € | 0,00 € |

**Vérifications**
- 320 + 40 + 40 = 400 commandes, donc tout le monde a un statut.
- Pour les commandes terminées, l'encaissé (26 210,00 €) est égal au CA.
- Pour chaque fichier : reçues = intégrées + rejetées (voir M2).

## M4 – Anomalies

| Anomalie | Comment je l'ai trouvée | Effet | Décision |
| --- | --- | --- | --- |
| Ligne d'article 7 en double | `GROUP BY` sur toutes les colonnes, `HAVING COUNT(*) > 1` | +33,75 € de CA en trop si on la garde | Je garde une seule ligne et je note l'autre dans les rejets |
| Ligne 801 avec une commande 9999 qui n'existe pas | `NOT EXISTS` sur les commandes | Montant rattaché à aucune commande ni aucun client | Rejetée et notée dans les rejets |
| 27 commandes avec 2 paiements de même montant et même date | `GROUP BY order_id, paid_on, amount_cents` | Ça ressemble à des doublons, mais les `payment_id` sont différents et la somme = le montant de la commande | Je les garde : c'est un paiement en 2 fois |
| Montants multipliés si on joint lignes et paiements | Comparaison jointure directe / totaux séparés | Lignes : 29 472,50 € au lieu de 26 210,00 €. Paiements : 52 420,00 € au lieu de 26 210,00 € | Calculer un total par commande avant de joindre |
| Le CA change selon le statut | `GROUP BY status` | Terminées seules : 26 210,00 € ; avec en attente : 29 433,75 € ; avec annulées : 32 717,50 € | Je ne compte que les commandes terminées |
| Les 40 commandes annulées ont des paiements encaissés | Jointure orders / payments avec `cancelled` et `captured` | 3 283,75 € encaissés sans vente | Je garde les paiements mais pas dans le CA. À demander : ont-ils été remboursés ? |

## A1 – Normalisation et jointures

Avec `planning_a_normaliser.csv` (le nom et le responsable de la salle sont répétés à chaque réservation) :
- **mise à jour** : si je change le responsable sur une seule ligne, la salle 1 a deux responsables ;
- **insertion** : je ne peux pas ajouter une salle sans réservation, car `reservation_id` est obligatoire ;
- **suppression** : en supprimant la seule réservation de la salle 2, je perds le nom de la salle et sa responsable.

En séparant une table `salles` et une table `reservations`, les trois problèmes disparaissent.

Jointures : avec un `INNER JOIN` entre clients et commandes, j'obtiens 150 clients. Avec un `LEFT JOIN`, j'en ai 180, car les 30 clients sans commande sont gardés.
