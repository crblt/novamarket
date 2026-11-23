# Rapport S3 – Benchmark

## Contexte

- Machine : MacBook Air (puce Apple), Docker Desktop, PostgreSQL 17.12, conteneur limité à 2 Go de RAM et 2 CPU.
- Données : schéma `benchmark`, créé avec `s3/generer.sql`. Ces ventes sont simulées et ne comptent pas dans le CA NovaMarket.
- Vérification (`sql/01_verif.sql`) : 10 000 000 lignes, table de 498 Mo, pas d'index sur `benchmark_sales` au départ.

## Requête et filtres choisis

```sql
SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = ...;
```

| Filtre | Lignes trouvées | Sélectivité |
| --- | --- | --- |
| store_id = 42 | 100 | très sélectif (0,001 % de la table) |
| store_id = 1 | 9 500 000 | peu sélectif (95 % de la table) |

## Protocole

1. Mesures sans index : `sql/02_mesures.sql`, sortie dans `resultats/avant_index.txt`.
2. Création de l'index sur `store_id` : `sql/03_index.sql`, sortie dans `resultats/index.txt`.
3. Les mêmes mesures avec l'index : `sql/02_mesures.sql`, sortie dans `resultats/apres_index.txt`.

Chaque requête est lancée 4 fois. La 1re est le premier passage. Je prends la médiane des 3 suivantes.

## Résultats (Execution Time)

| Filtre | Sans index : plan | 1er passage | 3 mesures | Médiane | Avec index : plan | 1er passage | 3 mesures | Médiane |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| store_id = 42 | Parallel Seq Scan | 168,1 ms | 186,3 / 190,9 / 196,4 ms | **190,9 ms** | Index Scan | 0,834 ms | 0,086 / 0,037 / 0,037 ms | **0,037 ms** |
| store_id = 1 | Parallel Seq Scan | 591,9 ms | 611,9 / 600,2 / 652,7 ms | **611,9 ms** | Parallel Seq Scan (index pas utilisé) | 656,3 ms | 848,2 / 757,3 / 708,5 ms | **757,3 ms** |

Pages lues (Buffers) :
- store_id = 42 sans index : environ 63 700 pages, c'est-à-dire toute la table. Avec l'index : 103 pages.
- store_id = 1 : environ 63 700 pages avant et après, car la table est toujours lue en entier.

Coût de l'index (`resultats/index.txt`) : création en 1,8 s, taille de 66 Mo (la table fait 498 Mo).

## Analyse

**Filtre sélectif (store_id = 42).** Sans index, PostgreSQL lit les 10 millions de lignes pour en garder 100. Avec l'index, il va directement aux 100 lignes : on passe d'environ 191 ms à 0,04 ms, et de 63 700 à 103 pages lues. L'index est très utile ici.

**Index inefficace (store_id = 1).** Ce filtre garde 95 % des lignes. PostgreSQL n'utilise pas l'index et continue de lire toute la table (Seq Scan), car passer par l'index pour presque toutes les lignes coûterait plus cher. Les temps sont du même ordre avant et après. L'écart (612 ms contre 757 ms) vient des variations de la machine et du cache, pas de l'index, puisque le plan est le même. Un index présent n'est donc pas forcément utilisé, et il ne sert à rien pour un filtre peu sélectif.

**Premier passage.** Avec l'index, le 1er passage est plus lent (0,834 ms) que les suivants (0,037 ms). Au 1er passage, 98 pages ont été lues depuis le disque (`read=98`). Ensuite, elles étaient déjà en mémoire (`shared hit=103`). C'est pour ça que je mets le 1er passage à part.

**Jointure qui multiplie les lignes** (`sql/04_jointure_estimations.sql`). Le magasin 42 a 100 ventes pour 1 010 000 centimes. Quand je joins avec `campaign_assignments`, j'obtiens 200 lignes et 2 020 000 centimes, car le magasin 42 est dans 2 campagnes (101 et 102). Chaque vente est comptée deux fois. Ce n'est pas une erreur dans les données : c'est un problème de grain (une ligne = une vente × une campagne). Il faut agréger avant de joindre, ou ne pas joindre les campagnes pour calculer un montant de ventes. C'est le même problème qu'en S1 avec les lignes d'articles et les paiements.

**Écart entre lignes estimées et réelles.** Avec `WHERE zone_id = 1 AND channel_id = 1`, PostgreSQL estime environ 42 500 lignes par worker (environ 127 500 au total). En réalité, il en trouve 333 333 par worker, soit 1 000 000 : il se trompe d'environ 8 fois. Il pense que les deux filtres sont indépendants (10 % × 10 % = 1 %), mais dans ce jeu `zone_id` et `channel_id` ont toujours la même valeur, donc 10 % des lignes passent. Ici le plan reste un Seq Scan, donc l'erreur ne change pas le résultat. Sur une requête plus compliquée, une mauvaise estimation peut faire choisir une mauvaise jointure.

## Limites

- Les temps dépendent de mon Mac, de Docker et du cache. Ils servent à comparer avant/après sur le même poste, pas comme valeurs absolues.
- La table (498 Mo) est plus grosse que la mémoire de PostgreSQL : à chaque lecture complète, la plupart des pages sont relues (`read`).
- Une seule colonne indexée et une seule requête testées.
