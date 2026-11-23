-- 02 : import des fichiers dans les tables de réception

\copy reception.customers (customer_id, customer_name, city) FROM '/s1/donnees/customers.csv' WITH (FORMAT csv, HEADER true)
\copy reception.orders (order_id, customer_id, ordered_on, status) FROM '/s1/donnees/orders.csv' WITH (FORMAT csv, HEADER true)
\copy reception.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents) FROM '/s1/donnees/order_items.csv' WITH (FORMAT csv, HEADER true)

-- Le NDJSON : une ligne = un objet JSON (même méthode que dans REFERENCE_SQL.md)
\copy reception.payments_json (document) FROM '/s1/donnees/payments.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')

INSERT INTO reception.payments (payment_id, order_id, paid_on, amount_cents, status)
SELECT r.payment_id, r.order_id, r.paid_on, r.amount_cents, r.status
FROM reception.payments_json
CROSS JOIN LATERAL jsonb_to_record(document)
    AS r(payment_id integer, order_id integer, paid_on date, amount_cents integer, status text);
