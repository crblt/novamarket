-- 05 : indicateurs
-- Les montants sont en centimes. Je divise par 100 seulement pour afficher en euros.

-- 1. Nombre de commandes par statut
SELECT status, COUNT(*) AS nb_commandes
FROM metier.orders
GROUP BY status
ORDER BY status;

-- 2. Clients sans commande
SELECT COUNT(*) AS clients_sans_commande
FROM metier.customers c
WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.customer_id = c.customer_id);

-- 3. Montant des lignes des commandes terminées (CA) et panier moyen
-- Panier moyen = CA / nombre de commandes terminées
SELECT COUNT(DISTINCT o.order_id) AS nb_commandes_terminees,
       SUM(i.quantity * i.unit_price_cents) AS ca_centimes,
       ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2) AS ca_euros,
       ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0 / COUNT(DISTINCT o.order_id), 2) AS panier_moyen_euros
FROM metier.orders o
INNER JOIN metier.order_items i ON i.order_id = o.order_id
WHERE o.status = 'completed';

-- 4. Rapprochement commandes / paiements
-- Je calcule d'abord un total par commande pour les lignes, puis un total par commande pour les paiements,
-- et seulement ensuite je les joins (sinon les montants sont multipliés, voir 06_anomalies.sql).
SELECT o.status,
       COUNT(*) AS nb_commandes,
       ROUND(SUM(l.montant_lignes) / 100.0, 2) AS commande_euros,
       ROUND(SUM(COALESCE(p.encaisse, 0)) / 100.0, 2) AS encaisse_euros,
       ROUND(SUM(COALESCE(p.en_attente, 0)) / 100.0, 2) AS en_attente_euros
FROM metier.orders o
INNER JOIN (
    SELECT order_id, SUM(quantity * unit_price_cents) AS montant_lignes
    FROM metier.order_items
    GROUP BY order_id
) l ON l.order_id = o.order_id
LEFT JOIN (
    SELECT order_id,
           SUM(CASE WHEN status = 'captured' THEN amount_cents ELSE 0 END) AS encaisse,
           SUM(CASE WHEN status = 'pending' THEN amount_cents ELSE 0 END) AS en_attente
    FROM metier.payments
    GROUP BY order_id
) p ON p.order_id = o.order_id
GROUP BY o.status
ORDER BY o.status;
