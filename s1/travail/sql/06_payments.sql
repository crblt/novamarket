-- 06 · Paiements (NDJSON) : contrôle, intégration, rejets
-- Étape supplémentaire R0 : la ligne doit être un objet JSON valide. Les champs sont ensuite
-- lus en text (->>) puis typés comme pour les CSV. Pas d'en-tête : ligne du fichier = rang.

CREATE TABLE reception.payments_ctrl AS
WITH j AS (
    SELECT b.rang,
           b.document,
           CASE WHEN pg_input_is_valid(b.document, 'jsonb') THEN b.document::jsonb END AS doc
    FROM reception.payments_brut AS b
), champs AS (
    SELECT rang,
           document,
           CASE WHEN jsonb_typeof(doc) = 'object' THEN doc END AS doc,
           doc ->> 'payment_id'   AS payment_id_brut,
           doc ->> 'order_id'     AS order_id_brut,
           doc ->> 'paid_on'      AS paid_on_brut,
           doc ->> 'amount_cents' AS amount_cents_brut,
           doc ->> 'status'       AS status_brut
    FROM j
)
SELECT rang,
       document AS document_brut,
       doc,
       payment_id_brut, order_id_brut, paid_on_brut, amount_cents_brut, status_brut,
       CASE WHEN pg_input_is_valid(payment_id_brut, 'integer') THEN payment_id_brut::integer END     AS payment_id,
       CASE WHEN pg_input_is_valid(order_id_brut, 'integer') THEN order_id_brut::integer END         AS order_id,
       CASE WHEN paid_on_brut ~ '^\d{4}-\d{2}-\d{2}$' AND pg_input_is_valid(paid_on_brut, 'date')
            THEN paid_on_brut::date END AS paid_on,
       CASE WHEN pg_input_is_valid(amount_cents_brut, 'integer') THEN amount_cents_brut::integer END AS amount_cents,
       status_brut AS status,
       NULL::text AS regle,
       NULL::text AS cause
FROM champs;

-- R0 · document illisible
UPDATE reception.payments_ctrl
SET regle = 'R0',
    cause = CASE WHEN nullif(btrim(document_brut), '') IS NULL THEN 'ligne vide'
                 ELSE 'JSON invalide ou qui n''est pas un objet' END
WHERE regle IS NULL AND doc IS NULL;

-- R1 · valeur obligatoire manquante (clé absente, null JSON ou chaîne vide)
UPDATE reception.payments_ctrl
SET regle = 'R1',
    cause = 'valeur manquante : ' || concat_ws(', ',
        CASE WHEN nullif(btrim(payment_id_brut), '') IS NULL THEN 'payment_id' END,
        CASE WHEN nullif(btrim(order_id_brut), '') IS NULL THEN 'order_id' END,
        CASE WHEN nullif(btrim(paid_on_brut), '') IS NULL THEN 'paid_on' END,
        CASE WHEN nullif(btrim(amount_cents_brut), '') IS NULL THEN 'amount_cents' END,
        CASE WHEN nullif(btrim(status_brut), '') IS NULL THEN 'status' END)
WHERE regle IS NULL
  AND (nullif(btrim(payment_id_brut), '') IS NULL OR nullif(btrim(order_id_brut), '') IS NULL
       OR nullif(btrim(paid_on_brut), '') IS NULL OR nullif(btrim(amount_cents_brut), '') IS NULL
       OR nullif(btrim(status_brut), '') IS NULL);

-- R2 · type invalide
UPDATE reception.payments_ctrl
SET regle = 'R2',
    cause = 'type invalide : ' || concat_ws(', ',
        CASE WHEN payment_id IS NULL THEN 'payment_id = ' || quote_literal(payment_id_brut) END,
        CASE WHEN order_id IS NULL THEN 'order_id = ' || quote_literal(order_id_brut) END,
        CASE WHEN paid_on IS NULL THEN 'paid_on = ' || quote_literal(paid_on_brut) END,
        CASE WHEN amount_cents IS NULL THEN 'amount_cents = ' || quote_literal(amount_cents_brut) END)
WHERE regle IS NULL
  AND (payment_id IS NULL OR order_id IS NULL OR paid_on IS NULL OR amount_cents IS NULL);

-- R3 · hors domaine
UPDATE reception.payments_ctrl
SET regle = 'R3',
    cause = concat_ws(' ; ',
        CASE WHEN payment_id <= 0 THEN 'payment_id non positif' END,
        CASE WHEN amount_cents <= 0 THEN 'montant non positif : ' || amount_cents END,
        CASE WHEN status NOT IN ('captured', 'pending') THEN 'status inconnu : ' || quote_literal(status) END)
WHERE regle IS NULL
  AND (payment_id <= 0 OR amount_cents <= 0 OR status NOT IN ('captured', 'pending'));

-- R4 · doublon exact / R5 · clé en conflit (sur payment_id : deux paiements de même montant
-- et de même date mais d'identifiants distincts ne sont PAS des doublons, cf. anomalies.sql)
WITH k AS (
    SELECT rang,
           count(*)  OVER (PARTITION BY payment_id) AS n_cle,
           count(*)  OVER (PARTITION BY payment_id, order_id, paid_on, amount_cents, status) AS n_identiques,
           min(rang) OVER (PARTITION BY payment_id, order_id, paid_on, amount_cents, status) AS rang_premier
    FROM reception.payments_ctrl
    WHERE regle IS NULL
)
UPDATE reception.payments_ctrl AS c
SET regle = CASE WHEN k.n_cle > k.n_identiques THEN 'R5' ELSE 'R4' END,
    cause = CASE WHEN k.n_cle > k.n_identiques
                 THEN 'payment_id ' || c.payment_id || ' reçu avec des contenus différents'
                 ELSE 'doublon exact de la ligne ' || k.rang_premier || ' du fichier' END
FROM k
WHERE c.rang = k.rang
  AND (k.n_cle > k.n_identiques OR k.rang > k.rang_premier);

-- R6 · commande inconnue
UPDATE reception.payments_ctrl AS c
SET regle = 'R6', cause = 'order_id ' || c.order_id || ' absent de metier.orders'
WHERE c.regle IS NULL
  AND NOT EXISTS (SELECT 1 FROM metier.orders AS o WHERE o.order_id = c.order_id);

INSERT INTO metier.payments (payment_id, order_id, paid_on, amount_cents, status)
SELECT payment_id, order_id, paid_on, amount_cents, status
FROM reception.payments_ctrl
WHERE regle IS NULL
ORDER BY payment_id;

INSERT INTO reception.rejets (source, rang, ligne_fichier, cle, regle, cause, contenu)
SELECT 'payments.ndjson', rang, rang, payment_id_brut, regle, cause,
       coalesce(doc, jsonb_build_object('document_brut', document_brut))
FROM reception.payments_ctrl
WHERE regle IS NOT NULL;
