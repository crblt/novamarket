# M4 · Tableau des anomalies

Requêtes : [`sql/anomalies.sql`](../sql/anomalies.sql) (codes A1–A9) et [`sql/indicateurs.sql`](../sql/indicateurs.sql) (I1–I5). Sorties : [`resultats/03_anomalies.txt`](resultats/03_anomalies.txt). Montants en euros, calculés en centimes.

| # | Anomalie | Détection | Effet mesuré | Décision |
| --- | --- | --- | --- | --- |
| 1 | **Doublon exact** dans `order_items.csv` : la ligne 802 répète la ligne 8 (`order_item_id` 7, commande 4, produit 5, 3 × 11,25 €). | A1 (`GROUP BY` sur toutes les colonnes `HAVING count(*) > 1`) ; règle R4 à l'import. | Intégrée telle quelle, la ligne ajouterait 33,75 € à la commande 4 (terminée) : CA de 26 243,75 € au lieu de 26 210,00 €. Avec la clé primaire, un `\copy` direct échouerait sur tout le fichier. | 1re occurrence intégrée, ligne 802 rejetée (R4) et journalisée. |
| 2 | **Référence orpheline** : ligne 803 (`order_item_id` 801) vers la commande 9999, inexistante. | A3 (`NOT EXISTS` sur la réception) ; règle R6. | 6,25 € sans commande, donc sans client, sans date ni statut : impossible à rattacher à un périmètre de CA. Bloquerait aussi un import direct (clé étrangère). | Rejetée (R6), journalisée, à signaler au fournisseur du fichier. Non réintégrée. |
| 3 | **Faux doublons de paiements** : 27 commandes ont deux paiements de même date et même montant (ex. commande 5 : paiements 5 et 6 à 27,50 €). | A4 (`GROUP BY order_id, paid_on, amount_cents, status HAVING count(*) > 1`) puis comparaison au montant commandé. | Les `payment_id` sont distincts et, dans les 27 cas, la somme des deux parts égale le montant commandé : c'est un paiement fractionné. Un dédoublonnage « métier » supprimerait à tort 1 013,75 € de paiements. | Conservés. Le dédoublonnage se fait sur l'identifiant (R4/R5), jamais sur le montant. |
| 4 | **Multiplication des montants** par la jointure `orders × order_items × payments`. | A5 : comparaison jointure naïve / pré-agrégation ; A1_jointures (5 stratégies). | Commandes terminées : 720 lignes de jointure pour 640 lignes d'articles. Lignes comptées 29 472,50 € au lieu de 26 210,00 € (+3 262,50 €, +12,4 %) ; paiements 52 420,00 € au lieu de 26 210,00 € (× 2, car chaque commande a 2 lignes). `SUM(DISTINCT)` ne corrige pas : il fusionne les parts égales (25 791,25 € capturés au lieu de 26 210,00 €). | Agréger chaque table enfant au grain commande avant de rapprocher (vues `v_commande_montant`, `v_commande_paiement`, `v_rapprochement`). Contrôles C3, C4, C5. |
| 5 | **Périmètre de statut** du chiffre d'affaires. | A6 : CA selon trois périmètres. | Terminées : 26 210,00 € (320 commandes). + en attente : 29 433,75 € (+3 223,75 €). Tous statuts : 32 717,50 € (+6 507,50 €, soit +24,8 %). | CA = commandes `completed` seulement. Les commandes `pending` sont suivies à part (3 223,75 € en attente de paiement), les `cancelled` sont exclues. |
| 6 | **Commandes annulées avec paiements capturés** : les 40 commandes annulées ont chacune 2 paiements `captured`. | A7, A8 ; typologie I5. | 3 283,75 € encaissés sans CA associé. Aucun remboursement n'existe dans les sources (`payments` ne connaît que `captured` et `pending`). Le total capturé (29 493,75 €) dépasse donc le CA (26 210,00 €). | Paiements intégrés (faits réels), exclus du CA, signalés à la finance. Hypothèse : remboursement traité hors des sources S1. À confirmer avec le métier. |
| 7 | **Clients sans commande** : 30 clients (identifiants 151 à 180). | I2 (`NOT EXISTS`) ; A1_jointures (INNER vs LEFT JOIN). | Pas une erreur de données, mais un `INNER JOIN` clients-commandes les fait disparaître ; un `COUNT(*)` après `LEFT JOIN` les compte comme une commande (430 au lieu de 400). | Compter avec `NOT EXISTS` ou `COUNT(colonne)` après `LEFT JOIN`. 60 clients n'ont aucune commande **terminée**. |
| 8 | **Dénominateur du panier moyen** ambigu. | I3 : trois dénominateurs comparés. | 81,91 € (÷ 320 commandes terminées), 65,53 € (÷ 400 commandes, hors périmètre), 40,95 € (÷ 640 lignes : prix moyen d'une ligne). | Panier moyen = CA des terminées ÷ commandes terminées ayant au moins une ligne (320). Contrôle C7 : aucune commande sans ligne. |
| 9 | **Catalogue (hors périmètre S1)** : `products.csv` répète le produit 3 (ligne 26 = ligne 4) ; le produit 6 a `first_listed_on` = 2026-09-15 mais apparaît dans 6 commandes antérieures (commandes 5, 22, 29, 46, 53, 70). | Lecture des fichiers reçus avec le kit, contrôle Python. | Une jointure lignes × produits doublerait les lignes du produit 3 ; la date de référencement contredit les ventes. | Non intégré en S1. À traiter (R4 + contrôle de date) quand le catalogue sera chargé. |

## Contrôles sans anomalie

| Contrôle | Résultat |
| --- | --- |
| Doublons exacts dans `customers`, `orders`, `payments` | aucun |
| Même identifiant avec contenus différents (R5), toutes sources | aucun |
| Commandes vers un client inconnu, paiements vers une commande inconnue | aucun |
| Paiement daté avant sa commande | aucun (tous les paiements sont du jour de la commande) |
| Paiement en attente sur une commande terminée, capture sur commande en attente | aucun |
| Écart commandé / payé (capturé + en attente) au grain commande | 0 commande sur 400 |
| Même produit deux fois dans une commande | aucun |
| Clés JSON inattendues dans `payments.ndjson` | aucune (5 clés attendues) |
