# Rapport S2 – Catalogue et analyses

## M1 – Catalogue

### Grain et relations

| Fichier | Une ligne = | Clé |
| --- | --- | --- |
| categories.csv | une catégorie | category_id |
| products.csv | une fiche produit | product_id |

- Une catégorie peut avoir une catégorie parente (`parent_category_id`, vide pour une racine). C'est une hiérarchie : Maison et Loisirs sont les deux racines.
- Une catégorie contient plusieurs produits (1–N).
- Un produit apparaît dans plusieurs lignes de commande (1–N), avec le même `product_id` que dans S1.

### Import (`sql/01_catalogue.sql`)

Même méthode qu'en S1 : réception sans clé, puis tables métier avec clés. Les catégories sont importées avant les produits.

| Fichier | Reçues | Intégrées | Rejetées |
| --- | --- | --- | --- |
| categories.csv | 10 | 10 | 0 |
| products.csv | 25 | 24 | 1 |

Rejet : le produit 3 apparaît deux fois à l'identique (doublon exact). J'en garde une seule ligne.

### Lien avec les ventes S1

- Les 24 produits vendus dans S1 sont tous dans le catalogue, et tous les produits du catalogue ont été vendus. J'ai donc ajouté une clé étrangère `order_items.product_id → products.product_id`.
- **Anomalie de date** : le produit 6 a une date de mise en vente au 15/09/2026, mais il apparaît dans 6 commandes passées avant cette date (du 01/09 au 14/09, dont 5 terminées). Ce n'est pas une évolution normale : c'est une incohérence démontrée entre le catalogue et les ventes. Je garde les ventes, car elles ont bien eu lieu, et je le signale. Soit la date du catalogue est fausse, soit ces ventes n'auraient pas dû être possibles.

## M2 – Analyses (`sql/02_analyses.sql`)

Périmètre : commandes terminées uniquement (CA = 26 210,00 €, comme en S1).

### Classement des produits (RANK)

Une CTE calcule d'abord le CA par produit (grain : une ligne = un produit). Ensuite, `RANK()` classe les produits :
- `rang_global` classe tous les produits ensemble ;
- `rang_dans_categorie` utilise `PARTITION BY category_id` et recommence le classement dans chaque catégorie.

Top 3 : produit 23 (2 733,75 €), produit 20 (2 430,00 €), produit 17 (2 126,25 €).

**Ex æquo** : les produits 7 et 18 ont tous les deux 715,00 €. `RANK` leur donne la place 15 aux deux, et le suivant est 17e (la place 16 est sautée). J'ai choisi `RANK` car deux produits avec le même CA doivent avoir la même place.

Clients : trois clients (9, 33, 57) sont ex æquo à la 1re place avec 363,75 €, et le suivant est 4e.

**Effet du doublon** : si je joins la table de réception des produits (avec le produit 3 en double), les ventes du produit 3 sont comptées deux fois. Il passe de 236,25 € (24e) à 472,50 € (21e), et le CA total passe à 26 446,25 € au lieu de 26 210,00 €.

### Évolution par mois (LAG et LEAD)

| Mois | Jours avec ventes | CA | Mois précédent (LAG) | Évolution | CA moyen par jour |
| --- | --- | --- | --- | --- | --- |
| septembre | 30 | 9 717,50 € | – | – | 323,92 € |
| octobre | 31 | 10 261,25 € | 9 717,50 € | +543,75 € | 331,01 € |
| novembre | 19 | 6 231,25 € | 10 261,25 € | −4 030,00 € | 327,96 € |

**Période incomplète** : novembre s'arrête au 19. La baisse de 4 030 € vient du mois incomplet, pas d'une vraie baisse des ventes. Le CA moyen par jour reste à peu près le même (environ 330 €). Il n'y a pas de mois manquant, donc `LAG` compare bien chaque mois au mois juste avant.

### Segmentation des clients (NTILE)

- Population : les 120 clients qui ont au moins une commande terminée.
- Mesure : CA des commandes terminées.
- Ordre : CA décroissant, puis `customer_id` pour que le résultat soit toujours le même.

| Quartile | Clients | CA min | CA max | CA total |
| --- | --- | --- | --- | --- |
| 1 | 30 | 270,00 € | 363,75 € | 9 277,50 € |
| 2 | 30 | 206,25 € | 266,25 € | 7 110,00 € |
| 3 | 30 | 167,50 € | 206,25 € | 5 691,25 € |
| 4 | 30 | 95,00 € | 167,50 € | 4 131,25 € |

**Limite** : `NTILE` fait des groupes de même taille. Des clients avec le même CA peuvent donc être coupés entre deux groupes : 206,25 € est à la fois dans le quartile 2 et le quartile 3, et 167,50 € dans le 3 et le 4.

### Hiérarchie des catégories (WITH RECURSIVE)

- Ancre : les catégories sans parent (Maison, Loisirs).
- Récursion : on ajoute les enfants niveau par niveau.
- Condition d'arrêt : `profondeur < 10`, pour ne pas tourner à l'infini s'il y avait un cycle.
- Contrôle : 10 catégories dans la table, 10 lignes dans l'arbre, 10 catégories différentes atteintes. Il n'y a donc ni cycle ni catégorie mal rattachée.

CA par famille (catégorie racine) :

| Famille | Produits | CA |
| --- | --- | --- |
| Loisirs | 12 | 17 966,25 € |
| Maison | 12 | 8 243,75 € |

Total = 26 210,00 € (le CA de S1), donc il n'y a pas de double comptage. Chaque produit est dans une seule catégorie, donc il compte une seule fois dans sa famille. Si j'avais additionné le CA à chaque niveau (Atelier puis Maison), le même produit aurait été compté plusieurs fois.
