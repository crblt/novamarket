-- S4 : vérifications après le chargement et dbt build
-- Lancer : docker compose exec -T postgres psql -X -U atelier -d novamarket < transformation/verifications.sql

-- 1. Volumes : source, staging, mart
SELECT 'fournisseur.offres (source)' AS etape, COUNT(*) AS lignes FROM fournisseur.offres
UNION ALL SELECT 'dbt_dev.stg_offres (staging)', COUNT(*) FROM dbt_dev.stg_offres
UNION ALL SELECT 'dbt_dev.mart_offres_produits (mart)', COUNT(*) FROM dbt_dev.mart_offres_produits
UNION ALL SELECT 'metier.products (catalogue)', COUNT(*) FROM metier.products;

-- 2. Pas de multiplication : offres et CA du mart = source
SELECT (SELECT SUM(nb_offres) FROM dbt_dev.mart_offres_produits) AS offres_dans_mart,
       (SELECT COUNT(*) FROM fournisseur.offres) AS offres_source,
       (SELECT SUM(ca_cents) FROM dbt_dev.mart_offres_produits) AS ca_mart_centimes,
       (SELECT SUM(i.quantity * i.unit_price_cents)
        FROM metier.order_items i
        INNER JOIN metier.orders o ON o.order_id = i.order_id
        WHERE o.status = 'completed') AS ca_s1_centimes;

-- 3. Quelques lignes du staging et du mart
SELECT * FROM dbt_dev.stg_offres ORDER BY offer_id LIMIT 5;
SELECT * FROM dbt_dev.mart_offres_produits ORDER BY product_id LIMIT 8;

-- 4. Produits sans offre fournisseur
SELECT product_id, product_name FROM dbt_dev.mart_offres_produits WHERE nb_offres = 0 ORDER BY product_id;

-- 5. Historique des chargements
SELECT lot_id, statut, lues, inserees, mises_a_jour, inchangees, rejetees, message
FROM fournisseur.lots
ORDER BY lance_le;
