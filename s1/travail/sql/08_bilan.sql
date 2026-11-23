-- 08 · Bilan des volumes : reçu = intégré + rejeté, sinon écart non expliqué

CREATE VIEW reception.v_bilan_import AS
WITH recu AS (
    SELECT 1 AS ordre, 'customers.csv'   AS source, count(*) AS lignes_recues FROM reception.customers_brut
    UNION ALL SELECT 2, 'orders.csv',      count(*) FROM reception.orders_brut
    UNION ALL SELECT 3, 'order_items.csv', count(*) FROM reception.order_items_brut
    UNION ALL SELECT 4, 'payments.ndjson', count(*) FROM reception.payments_brut
), integre AS (
    SELECT 'customers.csv' AS source, count(*) AS lignes_integrees FROM metier.customers
    UNION ALL SELECT 'orders.csv',      count(*) FROM metier.orders
    UNION ALL SELECT 'order_items.csv', count(*) FROM metier.order_items
    UNION ALL SELECT 'payments.ndjson', count(*) FROM metier.payments
), rejete AS (
    SELECT source, count(*) AS lignes_rejetees FROM reception.rejets GROUP BY source
)
SELECT r.ordre,
       r.source,
       r.lignes_recues,
       i.lignes_integrees,
       coalesce(j.lignes_rejetees, 0) AS lignes_rejetees,
       r.lignes_recues - i.lignes_integrees - coalesce(j.lignes_rejetees, 0) AS ecart_non_explique
FROM recu AS r
JOIN integre AS i USING (source)
LEFT JOIN rejete AS j USING (source);

\echo '== Bilan des volumes =='
SELECT source, lignes_recues, lignes_integrees, lignes_rejetees, ecart_non_explique
FROM reception.v_bilan_import
ORDER BY ordre;

\echo '== Rejets par règle =='
SELECT source, regle, count(*) AS lignes
FROM reception.rejets
GROUP BY source, regle
ORDER BY source, regle;

\echo '== Journal des rejets =='
SELECT source, ligne_fichier, cle, regle, cause, contenu
FROM reception.rejets
ORDER BY source, ligne_fichier;
