-- 02 · Réception
-- Chaque fichier est chargé tel quel : toutes les colonnes en text, aucune contrainte métier,
-- pour qu'aucune ligne ne soit perdue au chargement. `rang` = position de la ligne de données
-- dans le fichier (en-tête exclu) ; ligne du fichier = rang + 1 pour les CSV, rang pour le NDJSON.
-- HEADER match : psql refuse le fichier si l'en-tête ne correspond pas aux colonnes attendues.

CREATE TABLE reception.customers_brut (
    rang          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   text,
    customer_name text,
    city          text
);

CREATE TABLE reception.orders_brut (
    rang        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    text,
    customer_id text,
    ordered_on  text,
    status      text
);

CREATE TABLE reception.order_items_brut (
    rang             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_item_id    text,
    order_id         text,
    product_id       text,
    quantity         text,
    unit_price_cents text
);

-- NDJSON : une ligne = un document, stocké en text (un JSON invalide sera rejeté, pas bloquant).
CREATE TABLE reception.payments_brut (
    rang     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    document text
);

-- Journal des rejets : une ligne reçue rejetée = une ligne ici, avec la règle et la cause.
CREATE TABLE reception.rejets (
    rejet_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source        text   NOT NULL,
    rang          bigint NOT NULL,
    ligne_fichier bigint NOT NULL,
    cle           text,
    regle         text   NOT NULL,
    cause         text   NOT NULL,
    contenu       jsonb  NOT NULL,
    UNIQUE (source, rang)
);

COMMENT ON TABLE reception.rejets IS
    'R0 JSON invalide · R1 valeur manquante · R2 type invalide · R3 hors domaine · '
    'R4 doublon exact (1re occurrence conservée) · R5 clé en conflit · R6 référence orpheline';

\copy reception.customers_brut (customer_id, customer_name, city) FROM '/s1/donnees/customers.csv' WITH (FORMAT csv, HEADER match, ENCODING 'UTF8')
\copy reception.orders_brut (order_id, customer_id, ordered_on, status) FROM '/s1/donnees/orders.csv' WITH (FORMAT csv, HEADER match, ENCODING 'UTF8')
\copy reception.order_items_brut (order_item_id, order_id, product_id, quantity, unit_price_cents) FROM '/s1/donnees/order_items.csv' WITH (FORMAT csv, HEADER match, ENCODING 'UTF8')
\copy reception.payments_brut (document) FROM '/s1/donnees/payments.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02', ENCODING 'UTF8')
