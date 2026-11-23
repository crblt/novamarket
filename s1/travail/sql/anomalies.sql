-- Investigation des anomalies (M4) · lecture seule
--   docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/anomalies.sql
-- Les requêtes A1 à A3 lisent la réception (données brutes) ; A4 à A9 lisent le schéma metier.

\pset footer off

\echo '== A1 · Doublons exacts dans les fichiers reçus (toutes colonnes identiques) =='
SELECT 'customers.csv' AS source, count(*) - count(DISTINCT (customer_id, customer_name, city)) AS lignes_en_trop
FROM reception.customers_brut
UNION ALL
SELECT 'orders.csv', count(*) - count(DISTINCT (order_id, customer_id, ordered_on, status))
FROM reception.orders_brut
UNION ALL
SELECT 'order_items.csv', count(*) - count(DISTINCT (order_item_id, order_id, product_id, quantity, unit_price_cents))
FROM reception.order_items_brut
UNION ALL
SELECT 'payments.ndjson', count(*) - count(DISTINCT document::jsonb)
FROM reception.payments_brut;

\echo '-- détail des lignes d''articles répétées'
SELECT order_item_id, order_id, product_id, quantity, unit_price_cents,
       count(*) AS occurrences, array_agg(rang + 1 ORDER BY rang) AS lignes_fichier
FROM reception.order_items_brut
GROUP BY order_item_id, order_id, product_id, quantity, unit_price_cents
HAVING count(*) > 1;

\echo '== A2 · Identifiants répétés avec un contenu différent (conflits de clé) =='
SELECT 'order_items.csv' AS source, order_item_id AS cle, count(DISTINCT (order_id, product_id, quantity, unit_price_cents)) AS versions
FROM reception.order_items_brut GROUP BY order_item_id
HAVING count(DISTINCT (order_id, product_id, quantity, unit_price_cents)) > 1
UNION ALL
SELECT 'orders.csv', order_id, count(DISTINCT (customer_id, ordered_on, status))
FROM reception.orders_brut GROUP BY order_id
HAVING count(DISTINCT (customer_id, ordered_on, status)) > 1
UNION ALL
SELECT 'payments.ndjson', document::jsonb ->> 'payment_id', count(DISTINCT document::jsonb)
FROM reception.payments_brut GROUP BY document::jsonb ->> 'payment_id'
HAVING count(DISTINCT document::jsonb) > 1;
-- Aucune ligne attendue sur les fichiers fournis.

\echo '== A3 · Références orphelines dans la réception =='
SELECT 'order_items.csv -> orders' AS relation, i.rang + 1 AS ligne_fichier, i.order_item_id AS cle, i.order_id AS reference
FROM reception.order_items_brut AS i
WHERE NOT EXISTS (SELECT 1 FROM reception.orders_brut AS o WHERE o.order_id = i.order_id)
UNION ALL
SELECT 'payments.ndjson -> orders', p.rang, p.document::jsonb ->> 'payment_id', p.document::jsonb ->> 'order_id'
FROM reception.payments_brut AS p
WHERE NOT EXISTS (SELECT 1 FROM reception.orders_brut AS o WHERE o.order_id = p.document::jsonb ->> 'order_id')
UNION ALL
SELECT 'orders.csv -> customers', o.rang + 1, o.order_id, o.customer_id
FROM reception.orders_brut AS o
WHERE NOT EXISTS (SELECT 1 FROM reception.customers_brut AS c WHERE c.customer_id = o.customer_id);

\echo '== A4 · Paiements de même commande, même date et même montant : faux doublons ? =='
-- Identifiants distincts et somme égale au montant commandé : paiement fractionné en deux parts égales.
WITH paires AS (
    SELECT order_id, paid_on, amount_cents, status, count(*) AS n, array_agg(payment_id ORDER BY payment_id) AS ids
    FROM metier.payments
    GROUP BY order_id, paid_on, amount_cents, status
    HAVING count(*) > 1
)
SELECT count(*)                                                    AS groupes,
       sum(n)                                                      AS paiements_concernes,
       count(*) FILTER (WHERE r.capture_cents + r.attente_cents = r.montant_lignes_cents) AS somme_egale_au_commande,
       round(sum(p.amount_cents * (p.n - 1)) / 100.0, 2)           AS montant_perdu_si_dedoublonne_eur
FROM paires AS p
JOIN metier.v_rapprochement AS r USING (order_id);

\echo '-- exemples'
SELECT p.order_id, array_agg(p.payment_id ORDER BY p.payment_id) AS paiements, array_agg(p.amount_cents) AS montants,
       r.montant_lignes_cents
FROM metier.payments AS p
JOIN metier.v_rapprochement AS r USING (order_id)
WHERE p.order_id IN (5, 30, 60)
GROUP BY p.order_id, r.montant_lignes_cents
ORDER BY p.order_id;

\echo '== A5 · Multiplication des montants en joignant articles et paiements =='
-- Jointure naïve : chaque ligne d'article est répétée pour chaque paiement de la commande.
WITH naif AS (
    SELECT sum(i.quantity::bigint * i.unit_price_cents) AS lignes_cents,
           sum(p.amount_cents)                          AS paiements_cents,
           count(*)                                     AS lignes_jointure
    FROM metier.orders AS o
    JOIN metier.order_items AS i ON i.order_id = o.order_id
    JOIN metier.payments    AS p ON p.order_id = o.order_id
    WHERE o.status = 'completed'
), correct AS (
    SELECT sum(montant_lignes_cents) AS lignes_cents, sum(capture_cents + attente_cents) AS paiements_cents
    FROM metier.v_rapprochement
    WHERE status = 'completed'
)
SELECT 'jointure naïve orders x items x payments' AS methode, n.lignes_jointure,
       round(n.lignes_cents / 100.0, 2) AS lignes_eur, round(n.paiements_cents / 100.0, 2) AS paiements_eur
FROM naif AS n
UNION ALL
SELECT 'pré-agrégation au grain commande', NULL,
       round(c.lignes_cents / 100.0, 2), round(c.paiements_cents / 100.0, 2)
FROM correct AS c;

\echo '-- facteur de multiplication par commande terminée'
SELECT nb_lignes, nb_paiements, nb_lignes * nb_paiements AS lignes_apres_jointure,
       count(*) AS commandes,
       nb_paiements AS facteur_sur_montant_lignes, nb_lignes AS facteur_sur_montant_paiements
FROM metier.v_rapprochement
WHERE status = 'completed'
GROUP BY nb_lignes, nb_paiements
ORDER BY nb_lignes, nb_paiements;

\echo '== A6 · Impact du statut de commande sur le chiffre d''affaires =='
SELECT perimetre, commandes, round(montant_cents / 100.0, 2) AS montant_lignes_eur,
       round(montant_cents / 100.0 - first_value(montant_cents) OVER (ORDER BY ordre) / 100.0, 2) AS ecart_vs_terminees_eur
FROM (
    SELECT 1 AS ordre, 'terminées (retenu)' AS perimetre, count(*) AS commandes, sum(montant_lignes_cents) AS montant_cents
    FROM metier.v_commande_montant WHERE status = 'completed'
    UNION ALL
    SELECT 2, 'terminées + en attente', count(*), sum(montant_lignes_cents)
    FROM metier.v_commande_montant WHERE status IN ('completed', 'pending')
    UNION ALL
    SELECT 3, 'tous statuts (annulées incluses)', count(*), sum(montant_lignes_cents)
    FROM metier.v_commande_montant
) AS s
ORDER BY ordre;

\echo '== A7 · Commandes annulées dont les paiements sont capturés =='
SELECT count(*) AS commandes_annulees,
       count(*) FILTER (WHERE capture_cents > 0) AS avec_capture,
       round(sum(capture_cents) / 100.0, 2) AS capture_eur,
       sum(nb_paiements) AS paiements
FROM metier.v_rapprochement
WHERE status = 'cancelled';

\echo '== A8 · Cohérence des dates et des statuts de paiement =='
SELECT count(*) FILTER (WHERE p.paid_on < o.ordered_on)                         AS paiements_avant_commande,
       count(*) FILTER (WHERE p.paid_on > o.ordered_on)                         AS paiements_apres_commande,
       count(*) FILTER (WHERE p.status = 'pending'  AND o.status = 'completed') AS attente_sur_terminee,
       count(*) FILTER (WHERE p.status = 'captured' AND o.status = 'pending')   AS capture_sur_en_attente,
       count(*) FILTER (WHERE p.status = 'captured' AND o.status = 'cancelled') AS capture_sur_annulee
FROM metier.payments AS p
JOIN metier.orders AS o ON o.order_id = p.order_id;

\echo '== A9 · Même produit plusieurs fois dans une commande, clés JSON inattendues =='
SELECT 'commandes avec un produit répété' AS controle, count(*)::text AS resultat
FROM (SELECT order_id FROM metier.order_items GROUP BY order_id, product_id HAVING count(*) > 1) AS d
UNION ALL
SELECT 'clés présentes dans payments.ndjson',
       string_agg(DISTINCT k, ', ' ORDER BY k)
FROM reception.payments_brut, jsonb_object_keys(document::jsonb) AS k;
