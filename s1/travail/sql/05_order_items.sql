-- 05 · Lignes d'articles : contrôle, intégration, rejets (même principe que 03)

CREATE TABLE reception.order_items_ctrl AS
SELECT b.rang,
       b.order_item_id    AS order_item_id_brut,
       b.order_id         AS order_id_brut,
       b.product_id       AS product_id_brut,
       b.quantity         AS quantity_brut,
       b.unit_price_cents AS unit_price_cents_brut,
       CASE WHEN pg_input_is_valid(b.order_item_id, 'integer') THEN b.order_item_id::integer END       AS order_item_id,
       CASE WHEN pg_input_is_valid(b.order_id, 'integer') THEN b.order_id::integer END                 AS order_id,
       CASE WHEN pg_input_is_valid(b.product_id, 'integer') THEN b.product_id::integer END             AS product_id,
       CASE WHEN pg_input_is_valid(b.quantity, 'integer') THEN b.quantity::integer END                 AS quantity,
       CASE WHEN pg_input_is_valid(b.unit_price_cents, 'integer') THEN b.unit_price_cents::integer END AS unit_price_cents,
       NULL::text AS regle,
       NULL::text AS cause
FROM reception.order_items_brut AS b;

-- R1 · valeur obligatoire manquante
UPDATE reception.order_items_ctrl
SET regle = 'R1',
    cause = 'valeur manquante : ' || concat_ws(', ',
        CASE WHEN nullif(btrim(order_item_id_brut), '') IS NULL THEN 'order_item_id' END,
        CASE WHEN nullif(btrim(order_id_brut), '') IS NULL THEN 'order_id' END,
        CASE WHEN nullif(btrim(product_id_brut), '') IS NULL THEN 'product_id' END,
        CASE WHEN nullif(btrim(quantity_brut), '') IS NULL THEN 'quantity' END,
        CASE WHEN nullif(btrim(unit_price_cents_brut), '') IS NULL THEN 'unit_price_cents' END)
WHERE regle IS NULL
  AND (nullif(btrim(order_item_id_brut), '') IS NULL OR nullif(btrim(order_id_brut), '') IS NULL
       OR nullif(btrim(product_id_brut), '') IS NULL OR nullif(btrim(quantity_brut), '') IS NULL
       OR nullif(btrim(unit_price_cents_brut), '') IS NULL);

-- R2 · type invalide (un prix décimal comme 12.50 est rejeté : les montants sont en centimes entiers)
UPDATE reception.order_items_ctrl
SET regle = 'R2',
    cause = 'type invalide : ' || concat_ws(', ',
        CASE WHEN order_item_id IS NULL THEN 'order_item_id = ' || quote_literal(order_item_id_brut) END,
        CASE WHEN order_id IS NULL THEN 'order_id = ' || quote_literal(order_id_brut) END,
        CASE WHEN product_id IS NULL THEN 'product_id = ' || quote_literal(product_id_brut) END,
        CASE WHEN quantity IS NULL THEN 'quantity = ' || quote_literal(quantity_brut) END,
        CASE WHEN unit_price_cents IS NULL THEN 'unit_price_cents = ' || quote_literal(unit_price_cents_brut) END)
WHERE regle IS NULL
  AND (order_item_id IS NULL OR order_id IS NULL OR product_id IS NULL
       OR quantity IS NULL OR unit_price_cents IS NULL);

-- R3 · hors domaine
UPDATE reception.order_items_ctrl
SET regle = 'R3',
    cause = concat_ws(' ; ',
        CASE WHEN order_item_id <= 0 THEN 'order_item_id non positif' END,
        CASE WHEN product_id <= 0 THEN 'product_id non positif' END,
        CASE WHEN quantity <= 0 THEN 'quantité non positive : ' || quantity END,
        CASE WHEN unit_price_cents < 0 THEN 'prix négatif : ' || unit_price_cents END)
WHERE regle IS NULL
  AND (order_item_id <= 0 OR product_id <= 0 OR quantity <= 0 OR unit_price_cents < 0);

-- R4 · doublon exact / R5 · clé en conflit
WITH k AS (
    SELECT rang,
           count(*)  OVER (PARTITION BY order_item_id) AS n_cle,
           count(*)  OVER (PARTITION BY order_item_id, order_id, product_id, quantity, unit_price_cents) AS n_identiques,
           min(rang) OVER (PARTITION BY order_item_id, order_id, product_id, quantity, unit_price_cents) AS rang_premier
    FROM reception.order_items_ctrl
    WHERE regle IS NULL
)
UPDATE reception.order_items_ctrl AS c
SET regle = CASE WHEN k.n_cle > k.n_identiques THEN 'R5' ELSE 'R4' END,
    cause = CASE WHEN k.n_cle > k.n_identiques
                 THEN 'order_item_id ' || c.order_item_id || ' reçu avec des contenus différents'
                 ELSE 'doublon exact de la ligne ' || (k.rang_premier + 1) || ' du fichier' END
FROM k
WHERE c.rang = k.rang
  AND (k.n_cle > k.n_identiques OR k.rang > k.rang_premier);

-- R6 · commande inconnue (absente ou rejetée)
UPDATE reception.order_items_ctrl AS c
SET regle = 'R6', cause = 'order_id ' || c.order_id || ' absent de metier.orders'
WHERE c.regle IS NULL
  AND NOT EXISTS (SELECT 1 FROM metier.orders AS o WHERE o.order_id = c.order_id);

INSERT INTO metier.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents)
SELECT order_item_id, order_id, product_id, quantity, unit_price_cents
FROM reception.order_items_ctrl
WHERE regle IS NULL
ORDER BY order_item_id;

INSERT INTO reception.rejets (source, rang, ligne_fichier, cle, regle, cause, contenu)
SELECT 'order_items.csv', rang, rang + 1, order_item_id_brut, regle, cause,
       jsonb_build_object('order_item_id', order_item_id_brut, 'order_id', order_id_brut,
                          'product_id', product_id_brut, 'quantity', quantity_brut,
                          'unit_price_cents', unit_price_cents_brut)
FROM reception.order_items_ctrl
WHERE regle IS NOT NULL;
