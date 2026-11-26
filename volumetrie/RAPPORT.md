# Rapport S5 : streaming Hugging Face, PySpark et Hub

## M1 - Fiche source

| | |
|---|---|
| Dépôt | `DinoPonjevic/NYC_TaxiData` (Hugging Face) |
| Révision | `5941adbf8c0b9930e47002dc3103de3f9291360d` |
| Taille du dépôt | 371 fichiers Parquet, 39 350 805 895 octets (environ 39,35 Go) |
| Partition utilisée | `2024/yellow/yellow_tripdata_2024-01.parquet`, 41 899 074 octets (environ 41,9 Mo) |
| Colonnes | `Start_Zone` (code zone TLC), `Trip_Distance` (miles), `Trip_Duration` (secondes) |
| Licence du miroir | `unknown` |
| Source d'origine | TLC de New York, publiée sur NYC Open Data. Pas d'informations sur les passagers. |

Restriction : comme la licence du miroir n'est pas renseignée, on lit et on analyse les données, mais on ne republie pas ses lignes. Pour le Hub, on publie seulement des données synthétiques.

Preuve : `resultats/02_infos.txt` (commande `acces.py --infos`, qui lit les métadonnées sans télécharger les données).

**Pourquoi ne pas tout charger en mémoire ?** Le dépôt fait 39 Go en Parquet compressé. Une fois décompressé, c'est encore plus gros, bien plus que la RAM d'un ordinateur portable. Et on n'a pas besoin de tout pour l'exercice : on lit une seule partition, et seulement 10 000 lignes.

**Pandas, Hugging Face Datasets ou Spark :**
- **Pandas** charge tout le fichier en mémoire. C'est simple et rapide si les données tiennent dans la RAM.
- **Hugging Face Datasets en streaming** lit les lignes petit à petit, sans télécharger tout le dépôt. C'est bien pour explorer une grosse source et en sortir un extrait.
- **Spark** découpe les données en partitions et les traite en parallèle, avec un plan d'exécution optimisé. C'est fait pour les gros volumes, les jointures et les agrégations, sur une machine ou sur un cluster. Ici on l'utilise en local, avec 2 fils.

## M2 - Lecture en streaming

Script : `streaming/extraire.py`. Il utilise `ouvrir()` de `hf_datasets/acces.py` (avec `streaming=True`).

- Il parcourt au maximum 10 000 lignes (option `--limite`), puis s'arrête.
- Il compte chaque ligne parcourue **avant** de la filtrer.
- Il écrit les lignes bonnes dans `donnees/extraction.jsonl`.
- Il ferme le flux dans un bloc `finally`, même en cas d'erreur.
- Il écrit le bilan dans `donnees/bilan_extraction.json`, avec la source, la révision, la partition, la limite et les règles.

Le test d'accès est passé : `Streaming accessible ; colonnes : Start_Zone, Trip_Distance, Trip_Duration` (`resultats/03_acces.txt`).

| Lignes | Nombre |
|---|---|
| Parcourues | 10 000 |
| Retenues | 9 846 |
| Rejetées | 154 (142 avec distance <= 0, 12 avec durée > 4 h) |

Preuve : `resultats/04_extraction.txt`.

## M3 - Règles de qualité

| Règle | Pourquoi |
|---|---|
| Les 3 colonnes sont remplies et numériques | sinon on ne peut pas calculer |
| 0 < `Trip_Distance` <= 100 miles | une distance nulle ou négative est une erreur, et plus de 100 miles n'est pas réaliste pour un taxi en ville |
| 0 < `Trip_Duration` <= 14 400 s (4 h) | une durée nulle est une erreur, et plus de 4 h est sûrement un compteur oublié |

Dans la partition, il n'y avait aucune valeur manquante et aucune erreur de type. Les rejets viennent tous des distances à 0 et des durées trop longues.

L'extrait est écrit avec les types déjà corrigés (zone en entier, distance et durée en décimal) et avec le même schéma que le fichier de secours. Il sert d'entrée à Spark. La provenance et la sélection sont notées dans le bilan.

Limite : on ne garde que les 10 000 premières lignes de janvier, donc l'extrait n'est pas représentatif de tout le mois.

## M4 - Pipeline PySpark

Script : `spark/pipeline.py`. Il prend en arguments le fichier d'entrée et un dossier de sortie neuf.

Ce que fait le script, dans l'ordre :
1. Il démarre Spark en local (2 fils) et lit le JSONL. Il affiche le schéma.
2. Il type les colonnes (`zone_id` en entier, `distance_miles` et `duree_s` en décimal).
3. Il refait les filtres de M3, au cas où le fichier d'entrée ne serait pas propre.
4. Il calcule `distance_km` (miles x 1,609344) et `vitesse_kmh`.
5. Il lit la table des zones et contrôle sa clé : 265 lignes, 265 clés différentes, 0 clé vide. La clé est unique, donc la jointure ne peut pas créer de doublons.
6. Il cherche les trajets dont la zone n'est pas dans la table (`left_anti`).
7. Il fait la jointure en `left` pour ne perdre aucun trajet, puis compare les volumes.
8. Il agrège par arrondissement : nombre de trajets, distance moyenne, durée moyenne et vitesse moyenne. On agrège par arrondissement parce qu'il n'y en a que quelques-uns, donc le résultat est lisible. Cela permet de comparer les types de trajets.
9. Il affiche les partitions et `explain()`.
10. Il écrit le Parquet (erreur si le dossier existe déjà), le relit et vérifie le total.

### Résultats sur l'extrait réel (`resultats/05_spark.txt`)

- Lignes lues : 9 846. Après filtre : 9 846. Rien n'est enlevé, parce que l'extrait était déjà propre.
- Trajets sans zone connue : 0.
- Avant jointure : 9 846, après jointure : 9 846. La jointure n'ajoute pas de lignes.
- Total des trajets dans le Parquet relu : 9 846. C'est le bon total.

| Arrondissement | Trajets | Distance moy. (km) | Durée moy. (min) | Vitesse moy. (km/h) |
|---|---|---|---|---|
| Manhattan | 9 421 | 4,12 | 15,5 | 16,9 |
| Queens | 306 | 20,1 | 23,6 | 49,2 |
| Brooklyn | 87 | 7,06 | 18,7 | 21,4 |
| Unknown | 18 | 5,09 | 20,3 | 15,2 |
| Bronx | 10 | 3,73 | 10,3 | 19,3 |
| N/A | 4 | 11,6 | 12,7 | 51,9 |

Ce qu'on voit : presque tous les trajets partent de Manhattan. Ce sont des trajets courts et lents, à cause de la circulation. Ceux du Queens sont longs et rapides, sûrement à cause des aéroports (JFK et LaGuardia) et des voies rapides. `Unknown` et `N/A` sont les zones 264 et 265 de la table TLC (zone inconnue et hors de New York). Elles existent dans la table, donc la jointure les trouve.

### Résultats sur le fichier de secours (`resultats/06_spark_secours.txt`)

On a aussi lancé le pipeline sur `secours/trajets_fictifs.jsonl` pour vérifier que les contrôles marchent :
- Lignes lues : 6. Après filtre : 5 (la distance de -2,0 est enlevée).
- Trajets sans zone connue : 1 (la zone `999`).
- Avant jointure : 5, après jointure : 5. Le trajet sans zone est gardé et classé en « Zone inconnue ».

### Plan d'exécution (`explain()`)

Le plan se lit de bas en haut :
- `FileScan json` lit seulement les 3 colonnes. Les filtres sont déjà appliqués pendant la lecture (`PushedFilters`).
- `Filter` et `Project` font les filtres, les conversions de type et les colonnes calculées.
- `BroadcastHashJoin ... LeftOuter` : la table des zones est petite, donc Spark l'envoie en entier à chaque tâche (broadcast). Il n'a pas besoin de redistribuer les trajets pour faire la jointure.
- `HashAggregate (partial_...)`, puis `Exchange hashpartitioning(arrondissement)`, puis `HashAggregate` : Spark fait un premier calcul partiel dans chaque partition. Il regroupe ensuite les lignes par arrondissement (shuffle), puis finit le calcul.
- `Exchange rangepartitioning` puis `Sort` : le tri final par nombre de trajets.
- `AdaptiveSparkPlan` et `AQEShuffleRead coalesced` : Spark adapte le plan pendant l'exécution. Il regroupe les petites partitions après le shuffle.

Partitions : 1 pour les trajets et 1 pour le résultat. Le fichier ne fait que 0,8 Mo, alors que Spark découpe par défaut en blocs de 128 Mo. Avec plus de données, il y aurait plus de partitions.

## M5 - Publication sur le Hub

Dépôt **privé** : https://huggingface.co/datasets/crblt/novamarket-s5-exercice

Contenu du dossier `publication/` (les seuls fichiers envoyés) :
- `README.md` : la Dataset Card, faite à partir de `documentation/DATASET_CARD_MODELE.md` (provenance, grain, colonnes et unités, contrôles, limites, usage, révisions) ;
- `trajets_synthetiques.jsonl` : les trajets inventés du fichier de secours du kit.

On publie des données synthétiques, et pas des lignes du dataset taxi, parce que la licence du miroir est `unknown`.

| Révision | SHA | Contenu |
|---|---|---|
| v1 « premier jeu vérifié » | `0bb7db6950a40499991e856330c9eb7efcf420a6` | 6 lignes, sans filtre |
| v2 « changement documenté » | `a3664d665c6ceb17814be2cf8cc7b7b826da131f` | 4 lignes : la distance négative (-2.0) et la zone `999` sont enlevées. Changement expliqué dans la partie « Révisions » de la Dataset Card. |

Vérification : on a retéléchargé `README.md` et le fichier de données à chaque SHA avec `hf download ... --revision`. On trouve 6 lignes pour la v1 et 4 pour la v2, et `diff` montre exactement les 2 lignes enlevées (`resultats/09_verif_revisions.txt`). Les liens des deux commits sont dans `resultats/07_hub_v1.txt` et `resultats/08_hub_v2.txt`.

Commandes utilisées (depuis `novamarket/`) :

```bash
hf auth login            # token de type Write collé dans l'invite, jamais écrit dans un fichier
hf auth whoami
repo="crblt/novamarket-s5-exercice"
hf repo create "$repo" --repo-type dataset --private
hf upload "$repo" ./publication . --repo-type dataset --exclude ".DS_Store" --commit-message "v1 : premier jeu vérifié"
# modification des données et de la Dataset Card
hf upload "$repo" ./publication . --repo-type dataset --exclude ".DS_Store" --commit-message "v2 : changement documenté"
hf download "$repo" README.md trajets_synthetiques.jsonl --repo-type dataset --revision "$sha_v1" --local-dir /tmp/s5_v1
hf download "$repo" README.md trajets_synthetiques.jsonl --repo-type dataset --revision "$sha_v2" --local-dir /tmp/s5_v2
```

Sécurité : le token n'est ni dans GitHub, ni dans les scripts, ni dans les fichiers de résultats. En cas de fuite, il faut le révoquer sur Hugging Face, lancer `hf auth logout` et en créer un nouveau.

Comme le dépôt est privé, le formateur doit être autorisé à y accéder pour le voir.

## Relancer

Depuis `novamarket/`, dans un nouveau Terminal :

```bash
source .venv/bin/activate
python -m pip install -r requirements-v3.txt -r volumetrie/requirements.txt
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
export SPARK_LOCAL_IP=127.0.0.1
export PYSPARK_PYTHON="$(command -v python)"
export PYSPARK_SUBMIT_ARGS="--driver-memory 1g pyspark-shell"
python volumetrie/spark/verifier.py
python volumetrie/hf_datasets/acces.py --infos
HF_HUB_DISABLE_XET=1 python volumetrie/hf_datasets/acces.py
HF_HUB_DISABLE_XET=1 python volumetrie/streaming/extraire.py
python volumetrie/spark/pipeline.py volumetrie/donnees/extraction.jsonl volumetrie/sorties/essai1
python volumetrie/spark/pipeline.py volumetrie/secours/trajets_fictifs.jsonl volumetrie/sorties/essai_secours
```

Les commandes Spark ont besoin d'un dossier de sortie neuf à chaque fois. `volumetrie/sorties/` n'est pas envoyé sur GitHub.

## Limites

- Java : le livret demande Java 21. Sur mon Mac il y a Java 22, et Spark 4.1.1 a quand même fonctionné (`resultats/01_verifier.txt`).
- On n'a lu que 10 000 lignes d'une seule partition, donc les moyennes ne valent pas pour tout le mois.
- Les distances sont stockées en float dans le Parquet, d'où des valeurs comme `1.7200000286`.
