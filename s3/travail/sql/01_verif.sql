-- S3 : vérifications après la génération (s3/generer.sql)

SELECT COUNT(*) AS nb_lignes FROM benchmark.benchmark_sales;
SELECT pg_size_pretty(pg_total_relation_size('benchmark.benchmark_sales')) AS taille_table;

-- Nombre de lignes pour les deux magasins que je vais filtrer
SELECT store_id, COUNT(*) AS nb_lignes
FROM benchmark.benchmark_sales
WHERE store_id IN (1, 42)
GROUP BY store_id;

-- Index existants sur le schéma benchmark (avant mon index, il ne doit y avoir que la clé de campaign_assignments)
\di benchmark.*
