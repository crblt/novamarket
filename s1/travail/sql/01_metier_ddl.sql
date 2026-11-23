-- 01 · Modèle métier
-- Ordre de création = ordre d'import : customers -> orders -> order_items / payments.
-- Montants en centimes (integer) : pas de flottant, pas d'arrondi à l'import.
-- Les index sur les clés étrangères sont volontairement laissés à la séance S3 (plans et index).

CREATE TABLE metier.customers (
    customer_id   integer PRIMARY KEY CHECK (customer_id > 0),
    customer_name text    NOT NULL,
    city          text    NOT NULL
);

CREATE TABLE metier.orders (
    order_id    integer PRIMARY KEY CHECK (order_id > 0),
    customer_id integer NOT NULL REFERENCES metier.customers (customer_id),
    ordered_on  date    NOT NULL,
    status      text    NOT NULL CHECK (status IN ('completed', 'pending', 'cancelled'))
);

CREATE TABLE metier.order_items (
    order_item_id    integer PRIMARY KEY CHECK (order_item_id > 0),
    order_id         integer NOT NULL REFERENCES metier.orders (order_id),
    -- Pas de clé étrangère : le catalogue produits est hors périmètre S1 (SOURCES.md).
    product_id       integer NOT NULL CHECK (product_id > 0),
    quantity         integer NOT NULL CHECK (quantity > 0),
    -- Prix de la transaction (peut différer du catalogue) ; 0 autorisé pour un article offert.
    unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0)
);

CREATE TABLE metier.payments (
    payment_id   integer PRIMARY KEY CHECK (payment_id > 0),
    order_id     integer NOT NULL REFERENCES metier.orders (order_id),
    paid_on      date    NOT NULL,
    amount_cents integer NOT NULL CHECK (amount_cents > 0),
    status       text    NOT NULL CHECK (status IN ('captured', 'pending'))
);

COMMENT ON TABLE metier.customers   IS 'Grain : un client';
COMMENT ON TABLE metier.orders      IS 'Grain : une commande (N commandes par client)';
COMMENT ON TABLE metier.order_items IS 'Grain : une ligne d''article (N lignes par commande)';
COMMENT ON TABLE metier.payments    IS 'Grain : une opération de paiement (N paiements par commande)';
COMMENT ON COLUMN metier.order_items.unit_price_cents IS 'Prix unitaire de la transaction, en centimes d''euro';
COMMENT ON COLUMN metier.payments.amount_cents       IS 'Montant de l''opération, en centimes d''euro';
COMMENT ON COLUMN metier.payments.paid_on            IS 'Date d''enregistrement ; date de saisie si status = pending';
