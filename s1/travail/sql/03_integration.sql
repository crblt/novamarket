-- 03 : passage de la réception vers le métier
-- Pour chaque fichier :
--   1. je note les doublons exacts dans le journal des rejets
--   2. j'intègre les lignes sans doublon (SELECT DISTINCT) dont le parent existe
--   3. je note les lignes dont le parent n'existe pas (orphelins)
-- Ordre : clients, puis commandes, puis lignes d'articles et paiements.

-- ===== Clients =====
INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT 'customers.csv', customer_id, 'doublon exact', COUNT(*) - 1
FROM reception.customers
GROUP BY customer_id, customer_name, city
HAVING COUNT(*) > 1;

INSERT INTO metier.customers (customer_id, customer_name, city)
SELECT DISTINCT customer_id, customer_name, city
FROM reception.customers;

-- ===== Commandes =====
INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT 'orders.csv', order_id, 'doublon exact', COUNT(*) - 1
FROM reception.orders
GROUP BY order_id, customer_id, ordered_on, status
HAVING COUNT(*) > 1;

INSERT INTO metier.orders (order_id, customer_id, ordered_on, status)
SELECT DISTINCT o.order_id, o.customer_id, o.ordered_on, o.status
FROM reception.orders o
WHERE EXISTS (SELECT 1 FROM metier.customers c WHERE c.customer_id = o.customer_id);

INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT DISTINCT 'orders.csv', o.order_id, 'client inexistant : ' || o.customer_id, 1
FROM reception.orders o
WHERE NOT EXISTS (SELECT 1 FROM metier.customers c WHERE c.customer_id = o.customer_id);

-- ===== Lignes d'articles =====
INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT 'order_items.csv', order_item_id, 'doublon exact', COUNT(*) - 1
FROM reception.order_items
GROUP BY order_item_id, order_id, product_id, quantity, unit_price_cents
HAVING COUNT(*) > 1;

INSERT INTO metier.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents)
SELECT DISTINCT i.order_item_id, i.order_id, i.product_id, i.quantity, i.unit_price_cents
FROM reception.order_items i
WHERE EXISTS (SELECT 1 FROM metier.orders o WHERE o.order_id = i.order_id);

INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT DISTINCT 'order_items.csv', i.order_item_id, 'commande inexistante : ' || i.order_id, 1
FROM reception.order_items i
WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.order_id = i.order_id);

-- ===== Paiements =====
INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT 'payments.ndjson', payment_id, 'doublon exact', COUNT(*) - 1
FROM reception.payments
GROUP BY payment_id, order_id, paid_on, amount_cents, status
HAVING COUNT(*) > 1;

INSERT INTO metier.payments (payment_id, order_id, paid_on, amount_cents, status)
SELECT DISTINCT p.payment_id, p.order_id, p.paid_on, p.amount_cents, p.status
FROM reception.payments p
WHERE EXISTS (SELECT 1 FROM metier.orders o WHERE o.order_id = p.order_id);

INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT DISTINCT 'payments.ndjson', p.payment_id, 'commande inexistante : ' || p.order_id, 1
FROM reception.payments p
WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.order_id = p.order_id);
