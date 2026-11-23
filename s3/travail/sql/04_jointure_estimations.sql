-- S3 : jointure qui multiplie les lignes, et écart entre lignes estimées et réelles

-- 1. Ventes du magasin 42 seules
SELECT COUNT(*) AS nb_ventes, SUM(amount_cents) AS montant
FROM benchmark.benchmark_sales
WHERE store_id = 42;

-- 2. Les mêmes ventes jointes aux campagnes : le magasin 42 est dans 2 campagnes (101 et 102),
-- donc chaque vente apparaît 2 fois et le montant est doublé.
SELECT COUNT(*) AS nb_lignes, SUM(s.amount_cents) AS montant
FROM benchmark.benchmark_sales s
INNER JOIN benchmark.campaign_assignments c ON c.store_id = s.store_id
WHERE s.store_id = 42;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), SUM(s.amount_cents)
FROM benchmark.benchmark_sales s
INNER JOIN benchmark.campaign_assignments c ON c.store_id = s.store_id
WHERE s.store_id = 42;

-- 3. Estimation fausse : zone_id et channel_id ont toujours la même valeur dans ce jeu.
-- PostgreSQL pense que les deux filtres sont indépendants (10 % x 10 % = 1 %),
-- alors qu'en réalité 10 % des lignes passent.
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM benchmark.benchmark_sales WHERE zone_id = 1 AND channel_id = 1;
