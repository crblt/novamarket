-- S3 : mesures. Le même fichier est lancé avant puis après l'index.
-- Chaque requête est lancée 4 fois : la 1re est le premier passage, les 3 suivantes servent pour la médiane.

-- Filtre 1 : très sélectif, store_id = 42 (environ 100 lignes sur 10 millions)
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 42;
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 42;
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 42;
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 42;

-- Filtre 2 : peu sélectif, store_id = 1 (environ 9,5 millions de lignes)
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1;
