-- 06 : recherche des anomalies

-- 1. Doublons exacts dans les lignes d'articles (fichier brut)
SELECT order_item_id, order_id, product_id, quantity, unit_price_cents, COUNT(*) AS nb
FROM reception.order_items
GROUP BY order_item_id, order_id, product_id, quantity, unit_price_cents
HAVING COUNT(*) > 1;

-- 2. Lignes d'articles dont la commande n'existe pas (orphelines)
SELECT i.*
FROM reception.order_items i
WHERE NOT EXISTS (SELECT 1 FROM reception.orders o WHERE o.order_id = i.order_id);

-- 3. Paiements en double ? Même commande, même date, même montant
-- Ce ne sont pas des doublons : payment_id différent et la somme = montant de la commande
SELECT order_id, paid_on, amount_cents, COUNT(*) AS nb_paiements
FROM metier.payments
GROUP BY order_id, paid_on, amount_cents
HAVING COUNT(*) > 1
ORDER BY order_id;

-- 4. Multiplication des montants quand on joint lignes ET paiements directement
-- Jointure directe (faux) :
SELECT SUM(i.quantity * i.unit_price_cents) AS lignes_centimes,
       SUM(p.amount_cents) AS paiements_centimes
FROM metier.orders o
INNER JOIN metier.order_items i ON i.order_id = o.order_id
INNER JOIN metier.payments p ON p.order_id = o.order_id
WHERE o.status = 'completed';

-- Sans jointure entre les deux (juste) :
SELECT (SELECT SUM(i.quantity * i.unit_price_cents)
        FROM metier.order_items i INNER JOIN metier.orders o ON o.order_id = i.order_id
        WHERE o.status = 'completed') AS lignes_centimes,
       (SELECT SUM(p.amount_cents)
        FROM metier.payments p INNER JOIN metier.orders o ON o.order_id = p.order_id
        WHERE o.status = 'completed') AS paiements_centimes;

-- 5. Impact du statut sur le CA
SELECT o.status, ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2) AS montant_euros
FROM metier.orders o
INNER JOIN metier.order_items i ON i.order_id = o.order_id
GROUP BY o.status
ORDER BY o.status;

-- 6. Commandes annulées qui ont quand même des paiements encaissés
SELECT COUNT(DISTINCT o.order_id) AS commandes_annulees,
       ROUND(SUM(p.amount_cents) / 100.0, 2) AS encaisse_euros
FROM metier.orders o
INNER JOIN metier.payments p ON p.order_id = o.order_id
WHERE o.status = 'cancelled' AND p.status = 'captured';
