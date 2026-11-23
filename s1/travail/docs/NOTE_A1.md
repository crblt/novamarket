# A1 · Note complémentaire : normalisation et stratégies de jointure

Scripts : [`sql/A1_normalisation.sql`](../sql/A1_normalisation.sql) et [`sql/A1_jointures.sql`](../sql/A1_jointures.sql). Sorties : [`resultats/04_A1_normalisation.txt`](resultats/04_A1_normalisation.txt), [`resultats/05_A1_jointures.txt`](resultats/05_A1_jointures.txt).

## 1. Table volontairement redondante (`planning_a_normaliser.csv`)

La table `planning(reservation_id, salle_id, salle_nom, responsable)` a pour clé `reservation_id`, mais `salle_nom` et `responsable` dépendent de `salle_id`, pas de la réservation : dépendance transitive, la table n'est pas en 3FN.

| Opération | Ce qui se passe dans `planning` | Dans le modèle normalisé `salles` + `reservations` |
| --- | --- | --- |
| **Mise à jour** : la salle 1 change de responsable | Modifier une seule des deux lignes laisse la salle 1 avec deux responsables (Ariane / Bruno). Rien ne l'empêche. | Une seule ligne à modifier dans `salles`. |
| **Insertion** : ouvrir l'Atelier Photo avant sa 1re réservation | Refusée : `reservation_id` est obligatoire. Il faudrait inventer une fausse réservation. | La salle 3 est créée seule ; le responsable peut rester inconnu. |
| **Suppression** : annuler la dernière réservation de la salle 2 | Le nom « Atelier Textile » et la responsable Sam disparaissent avec elle. | La réservation disparaît, la salle reste. |

En prime, la clé étrangère `reservations.salle_id → salles` refuse une réservation sur une salle inconnue. Avant de dédoublonner avec `SELECT DISTINCT`, le script vérifie qu'une salle n'a qu'une version (nom, responsable) dans la source : sinon le `DISTINCT` créerait deux lignes pour la même clé et l'insertion échouerait.

Le lien avec NovaMarket : la même logique a conduit à garder `customers`, `orders`, `order_items` et `payments` séparées, plutôt que d'aplatir la ville du client sur chaque ligne d'article.

## 2. Autres stratégies de jointure (commandes terminées)

| Stratégie | Lignes (centimes) | Capturé (centimes) | Verdict |
| --- | ---: | ---: | --- |
| S1 jointure naïve `orders ⋈ items ⋈ payments` | 2 947 250 | 5 242 000 | faux : chaque ligne répétée par paiement et inversement |
| S2 `SUM(DISTINCT)` sur l'ensemble | 88 500 | 216 125 | très faux : ne garde qu'une fois chaque montant distinct du fichier |
| S2b `SUM(DISTINCT)` par commande | 2 621 000 | 2 579 125 | faux : les paiements en deux parts égales sont fusionnés (418,75 € de captures perdus). Les lignes sont justes uniquement parce que les deux lignes d'une commande n'ont jamais le même montant ici |
| S3 pré-agrégation (sous-requêtes ou CTE groupées puis jointure 1-1) | 2 621 000 | 2 621 000 | juste, lisible, réutilisable en vue |
| S4 sous-requêtes scalaires corrélées | 2 621 000 | 2 621 000 | juste ; une sous-requête par commande et par mesure |
| S5 `CROSS JOIN LATERAL` | 2 621 000 | 2 621 000 | juste ; même logique que S4, écrite dans le `FROM` |

**Ce qu'on retient.** S3, S4 et S5 donnent le même résultat parce qu'elles ramènent chaque table enfant au grain commande avant de la combiner. `DISTINCT` n'est pas un correctif de grain : il confond « même ligne comptée deux fois » et « deux faits de même valeur ». S3 a été retenue pour les vues `metier.v_*` ; la comparaison des plans d'exécution de S3, S4 et S5 est un bon point de départ pour la séance S3.

**INNER JOIN contre LEFT JOIN.** Entre clients et commandes, un `INNER JOIN` compte 150 clients au lieu de 180 (les 30 sans commande disparaissent, environ 7 à 8 par ville). Après un `LEFT JOIN`, `COUNT(*)` vaut 430 car chaque client sans commande produit une ligne avec des `NULL` ; `COUNT(o.order_id)` vaut bien 400.
