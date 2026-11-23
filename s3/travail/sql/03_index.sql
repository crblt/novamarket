-- S3 : création de l'index sur store_id (la colonne des deux filtres)
-- \timing donne le temps de création.

DROP INDEX IF EXISTS benchmark.benchmark_sales_store_idx;

\timing on
CREATE INDEX benchmark_sales_store_idx ON benchmark.benchmark_sales (store_id);
\timing off

ANALYZE benchmark.benchmark_sales;

SELECT pg_size_pretty(pg_relation_size('benchmark.benchmark_sales_store_idx')) AS taille_index,
       pg_size_pretty(pg_relation_size('benchmark.benchmark_sales')) AS taille_table;
