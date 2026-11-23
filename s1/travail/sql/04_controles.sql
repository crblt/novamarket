-- 04 : contrôles après import
-- Pour chaque fichier : lignes reçues = lignes intégrées + lignes rejetées ?

SELECT 'customers.csv' AS fichier,
       (SELECT COUNT(*) FROM reception.customers) AS recues,
       (SELECT COUNT(*) FROM metier.customers) AS integrees,
       (SELECT COALESCE(SUM(nb_lignes), 0) FROM reception.rejets WHERE fichier = 'customers.csv') AS rejetees
UNION ALL
SELECT 'orders.csv',
       (SELECT COUNT(*) FROM reception.orders),
       (SELECT COUNT(*) FROM metier.orders),
       (SELECT COALESCE(SUM(nb_lignes), 0) FROM reception.rejets WHERE fichier = 'orders.csv')
UNION ALL
SELECT 'order_items.csv',
       (SELECT COUNT(*) FROM reception.order_items),
       (SELECT COUNT(*) FROM metier.order_items),
       (SELECT COALESCE(SUM(nb_lignes), 0) FROM reception.rejets WHERE fichier = 'order_items.csv')
UNION ALL
SELECT 'payments.ndjson',
       (SELECT COUNT(*) FROM reception.payments),
       (SELECT COUNT(*) FROM metier.payments),
       (SELECT COALESCE(SUM(nb_lignes), 0) FROM reception.rejets WHERE fichier = 'payments.ndjson');

-- Le journal des rejets
SELECT * FROM reception.rejets ORDER BY fichier, identifiant;
