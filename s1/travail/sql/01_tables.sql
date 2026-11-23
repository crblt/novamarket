-- 01 : création des tables
-- reception = les fichiers chargés tels quels, sans clé (pour pouvoir voir les doublons et les orphelins)
-- metier = les données propres, avec les clés et les contraintes

DROP SCHEMA IF EXISTS reception CASCADE;
DROP SCHEMA IF EXISTS metier CASCADE;
CREATE SCHEMA reception;
CREATE SCHEMA metier;

-- Tables de réception
CREATE TABLE reception.customers (
    customer_id integer,
    customer_name text,
    city text
);

CREATE TABLE reception.orders (
    order_id integer,
    customer_id integer,
    ordered_on date,
    status text
);

CREATE TABLE reception.order_items (
    order_item_id integer,
    order_id integer,
    product_id integer,
    quantity integer,
    unit_price_cents integer
);

CREATE TABLE reception.payments_json (
    document jsonb
);

CREATE TABLE reception.payments (
    payment_id integer,
    order_id integer,
    paid_on date,
    amount_cents integer,
    status text
);

-- Journal des rejets : quel fichier, quelle ligne, pourquoi
CREATE TABLE reception.rejets (
    fichier text,
    identifiant integer,
    raison text,
    nb_lignes integer
);

-- Tables métier
CREATE TABLE metier.customers (
    customer_id integer PRIMARY KEY,
    customer_name text NOT NULL,
    city text NOT NULL
);

CREATE TABLE metier.orders (
    order_id integer PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES metier.customers(customer_id),
    ordered_on date NOT NULL,
    status text NOT NULL CHECK (status IN ('completed', 'pending', 'cancelled'))
);

CREATE TABLE metier.order_items (
    order_item_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES metier.orders(order_id),
    product_id integer NOT NULL, -- pas de REFERENCES : le catalogue n'est pas dans S1
    quantity integer NOT NULL CHECK (quantity > 0),
    unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0)
);

CREATE TABLE metier.payments (
    payment_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES metier.orders(order_id),
    paid_on date NOT NULL,
    amount_cents integer NOT NULL CHECK (amount_cents > 0),
    status text NOT NULL CHECK (status IN ('captured', 'pending'))
);
