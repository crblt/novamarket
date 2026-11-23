-- 04 · Commandes : contrôle, intégration, rejets (même principe que 03)

CREATE TABLE reception.orders_ctrl AS
SELECT b.rang,
       b.order_id    AS order_id_brut,
       b.customer_id AS customer_id_brut,
       b.ordered_on  AS ordered_on_brut,
       b.status      AS status_brut,
       CASE WHEN pg_input_is_valid(b.order_id, 'integer') THEN b.order_id::integer END       AS order_id,
       CASE WHEN pg_input_is_valid(b.customer_id, 'integer') THEN b.customer_id::integer END AS customer_id,
       -- Format ISO AAAA-MM-JJ exigé par SOURCES.md, puis validité calendaire
       CASE WHEN b.ordered_on ~ '^\d{4}-\d{2}-\d{2}$' AND pg_input_is_valid(b.ordered_on, 'date')
            THEN b.ordered_on::date END AS ordered_on,
       b.status AS status,
       NULL::text AS regle,
       NULL::text AS cause
FROM reception.orders_brut AS b;

-- R1 · valeur obligatoire manquante
UPDATE reception.orders_ctrl
SET regle = 'R1',
    cause = 'valeur manquante : ' || concat_ws(', ',
        CASE WHEN nullif(btrim(order_id_brut), '') IS NULL THEN 'order_id' END,
        CASE WHEN nullif(btrim(customer_id_brut), '') IS NULL THEN 'customer_id' END,
        CASE WHEN nullif(btrim(ordered_on_brut), '') IS NULL THEN 'ordered_on' END,
        CASE WHEN nullif(btrim(status_brut), '') IS NULL THEN 'status' END)
WHERE regle IS NULL
  AND (nullif(btrim(order_id_brut), '') IS NULL OR nullif(btrim(customer_id_brut), '') IS NULL
       OR nullif(btrim(ordered_on_brut), '') IS NULL OR nullif(btrim(status_brut), '') IS NULL);

-- R2 · type invalide
UPDATE reception.orders_ctrl
SET regle = 'R2',
    cause = 'type invalide : ' || concat_ws(', ',
        CASE WHEN order_id IS NULL THEN 'order_id = ' || quote_literal(order_id_brut) END,
        CASE WHEN customer_id IS NULL THEN 'customer_id = ' || quote_literal(customer_id_brut) END,
        CASE WHEN ordered_on IS NULL THEN 'ordered_on = ' || quote_literal(ordered_on_brut) END)
WHERE regle IS NULL
  AND (order_id IS NULL OR customer_id IS NULL OR ordered_on IS NULL);

-- R3 · hors domaine (codes d'état sensibles à la casse)
UPDATE reception.orders_ctrl
SET regle = 'R3',
    cause = concat_ws(' ; ',
        CASE WHEN order_id <= 0 THEN 'order_id non positif' END,
        CASE WHEN status NOT IN ('completed', 'pending', 'cancelled')
             THEN 'status inconnu : ' || quote_literal(status) END)
WHERE regle IS NULL
  AND (order_id <= 0 OR status NOT IN ('completed', 'pending', 'cancelled'));

-- R4 · doublon exact / R5 · clé en conflit
WITH k AS (
    SELECT rang,
           count(*)  OVER (PARTITION BY order_id) AS n_cle,
           count(*)  OVER (PARTITION BY order_id, customer_id, ordered_on, status) AS n_identiques,
           min(rang) OVER (PARTITION BY order_id, customer_id, ordered_on, status) AS rang_premier
    FROM reception.orders_ctrl
    WHERE regle IS NULL
)
UPDATE reception.orders_ctrl AS c
SET regle = CASE WHEN k.n_cle > k.n_identiques THEN 'R5' ELSE 'R4' END,
    cause = CASE WHEN k.n_cle > k.n_identiques
                 THEN 'order_id ' || c.order_id || ' reçu avec des contenus différents'
                 ELSE 'doublon exact de la ligne ' || (k.rang_premier + 1) || ' du fichier' END
FROM k
WHERE c.rang = k.rang
  AND (k.n_cle > k.n_identiques OR k.rang > k.rang_premier);

-- R6 · client inconnu (absent ou rejeté)
UPDATE reception.orders_ctrl AS c
SET regle = 'R6', cause = 'customer_id ' || c.customer_id || ' absent de metier.customers'
WHERE c.regle IS NULL
  AND NOT EXISTS (SELECT 1 FROM metier.customers AS m WHERE m.customer_id = c.customer_id);

INSERT INTO metier.orders (order_id, customer_id, ordered_on, status)
SELECT order_id, customer_id, ordered_on, status
FROM reception.orders_ctrl
WHERE regle IS NULL
ORDER BY order_id;

INSERT INTO reception.rejets (source, rang, ligne_fichier, cle, regle, cause, contenu)
SELECT 'orders.csv', rang, rang + 1, order_id_brut, regle, cause,
       jsonb_build_object('order_id', order_id_brut, 'customer_id', customer_id_brut,
                          'ordered_on', ordered_on_brut, 'status', status_brut)
FROM reception.orders_ctrl
WHERE regle IS NOT NULL;
