-- A1 · Autres stratégies de jointure pour le rapprochement commandé / payé
--   docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/A1_jointures.sql
-- Même question posée cinq fois : montant des lignes et montant capturé des commandes terminées.

\pset footer off

\echo '== Comparaison des stratégies (commandes terminées) =='
WITH s1_naive AS (          -- jointure directe : produit lignes x paiements
    SELECT sum(i.quantity::bigint * i.unit_price_cents) AS lignes, sum(p.amount_cents) AS capture
    FROM metier.orders o
    JOIN metier.order_items i ON i.order_id = o.order_id
    JOIN metier.payments p    ON p.order_id = o.order_id AND p.status = 'captured'
    WHERE o.status = 'completed'
), s2_distinct AS (         -- « correctif » par SUM(DISTINCT) : fusionne des montants égaux légitimes
    SELECT sum(DISTINCT i.quantity::bigint * i.unit_price_cents) AS lignes, sum(DISTINCT p.amount_cents) AS capture
    FROM metier.orders o
    JOIN metier.order_items i ON i.order_id = o.order_id
    JOIN metier.payments p    ON p.order_id = o.order_id AND p.status = 'captured'
    WHERE o.status = 'completed'
), s2b_distinct_par_commande AS (  -- SUM(DISTINCT) commande par commande : toujours faux (2750 + 2750)
    SELECT sum(lignes) AS lignes, sum(capture) AS capture
    FROM (
        SELECT o.order_id,
               sum(DISTINCT i.quantity::bigint * i.unit_price_cents) AS lignes,
               sum(DISTINCT p.amount_cents) AS capture
        FROM metier.orders o
        JOIN metier.order_items i ON i.order_id = o.order_id
        JOIN metier.payments p    ON p.order_id = o.order_id AND p.status = 'captured'
        WHERE o.status = 'completed'
        GROUP BY o.order_id
    ) x
), s3_pre_agregation AS (   -- agrégation de chaque table à son grain, puis jointure 1-1
    SELECT sum(l.lignes) AS lignes, sum(coalesce(p.capture, 0)) AS capture
    FROM metier.orders o
    JOIN (SELECT order_id, sum(quantity::bigint * unit_price_cents) AS lignes
          FROM metier.order_items GROUP BY order_id) l ON l.order_id = o.order_id
    LEFT JOIN (SELECT order_id, sum(amount_cents) AS capture
               FROM metier.payments WHERE status = 'captured' GROUP BY order_id) p ON p.order_id = o.order_id
    WHERE o.status = 'completed'
), s4_sous_requetes AS (    -- sous-requêtes scalaires corrélées
    SELECT sum((SELECT sum(i.quantity::bigint * i.unit_price_cents) FROM metier.order_items i WHERE i.order_id = o.order_id)) AS lignes,
           sum((SELECT coalesce(sum(p.amount_cents), 0) FROM metier.payments p
                WHERE p.order_id = o.order_id AND p.status = 'captured')) AS capture
    FROM metier.orders o
    WHERE o.status = 'completed'
), s5_lateral AS (          -- LATERAL : agrégat calculé pour chaque commande
    SELECT sum(l.lignes) AS lignes, sum(p.capture) AS capture
    FROM metier.orders o
    CROSS JOIN LATERAL (SELECT sum(quantity::bigint * unit_price_cents) AS lignes
                        FROM metier.order_items i WHERE i.order_id = o.order_id) l
    CROSS JOIN LATERAL (SELECT coalesce(sum(amount_cents), 0) AS capture
                        FROM metier.payments p WHERE p.order_id = o.order_id AND p.status = 'captured') p
    WHERE o.status = 'completed'
)
SELECT 'S1 jointure naïve' AS strategie, lignes, capture, 'faux : montants multipliés' AS verdict FROM s1_naive
UNION ALL SELECT 'S2 SUM(DISTINCT) global', lignes, capture, 'faux : montants égaux fusionnés' FROM s2_distinct
UNION ALL SELECT 'S2b SUM(DISTINCT) par commande', lignes, capture, 'faux : parts égales fusionnées (lignes justes par hasard)' FROM s2b_distinct_par_commande
UNION ALL SELECT 'S3 pré-agrégation (CTE / sous-requête)', lignes, capture, 'juste' FROM s3_pre_agregation
UNION ALL SELECT 'S4 sous-requêtes corrélées', lignes, capture, 'juste' FROM s4_sous_requetes
UNION ALL SELECT 'S5 LATERAL', lignes, capture, 'juste' FROM s5_lateral;

\echo '== INNER JOIN contre LEFT JOIN : nombre de clients par ville =='
SELECT c.city,
       count(DISTINCT c.customer_id)                                              AS clients_left_join,
       count(DISTINCT c.customer_id) FILTER (WHERE o.order_id IS NOT NULL)        AS clients_inner_join,
       count(o.order_id)                                                          AS commandes
FROM metier.customers c
LEFT JOIN metier.orders o ON o.customer_id = c.customer_id
GROUP BY c.city
ORDER BY c.city;
-- Un INNER JOIN entre clients et commandes fait disparaître les 30 clients sans commande.

\echo '== Piège COUNT(*) après LEFT JOIN : un client sans commande compte pour 1 =='
SELECT count(*) AS count_etoile, count(o.order_id) AS count_colonne
FROM metier.customers c
LEFT JOIN metier.orders o ON o.customer_id = c.customer_id;
