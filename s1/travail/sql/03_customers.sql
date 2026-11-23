-- 03 · Clients : contrôle, intégration, rejets
-- Principe commun aux scripts 03 à 06 : une table *_ctrl porte les valeurs brutes, les valeurs
-- typées (NULL si non convertibles) et la première règle violée. Chaque règle est un UPDATE
-- appliqué uniquement aux lignes encore valides (regle IS NULL) : une ligne a une seule cause.

CREATE TABLE reception.customers_ctrl AS
SELECT b.rang,
       b.customer_id   AS customer_id_brut,
       b.customer_name AS customer_name_brut,
       b.city          AS city_brut,
       CASE WHEN pg_input_is_valid(b.customer_id, 'integer') THEN b.customer_id::integer END AS customer_id,
       nullif(btrim(b.customer_name), '') AS customer_name,
       nullif(btrim(b.city), '')          AS city,
       NULL::text AS regle,
       NULL::text AS cause
FROM reception.customers_brut AS b;

-- R1 · valeur obligatoire manquante
UPDATE reception.customers_ctrl
SET regle = 'R1',
    cause = 'valeur manquante : ' || concat_ws(', ',
        CASE WHEN nullif(btrim(customer_id_brut), '') IS NULL THEN 'customer_id' END,
        CASE WHEN customer_name IS NULL THEN 'customer_name' END,
        CASE WHEN city IS NULL THEN 'city' END)
WHERE regle IS NULL
  AND (nullif(btrim(customer_id_brut), '') IS NULL OR customer_name IS NULL OR city IS NULL);

-- R2 · type invalide
UPDATE reception.customers_ctrl
SET regle = 'R2', cause = 'type invalide : customer_id = ' || quote_literal(customer_id_brut)
WHERE regle IS NULL AND customer_id IS NULL;

-- R3 · hors domaine
UPDATE reception.customers_ctrl
SET regle = 'R3', cause = 'customer_id non positif'
WHERE regle IS NULL AND customer_id <= 0;

-- R4 · doublon exact (on garde la 1re occurrence) / R5 · même clé, contenu différent (tout rejeter)
WITH k AS (
    SELECT rang,
           count(*)   OVER (PARTITION BY customer_id) AS n_cle,
           count(*)   OVER (PARTITION BY customer_id, customer_name, city) AS n_identiques,
           min(rang)  OVER (PARTITION BY customer_id, customer_name, city) AS rang_premier
    FROM reception.customers_ctrl
    WHERE regle IS NULL
)
UPDATE reception.customers_ctrl AS c
SET regle = CASE WHEN k.n_cle > k.n_identiques THEN 'R5' ELSE 'R4' END,
    cause = CASE WHEN k.n_cle > k.n_identiques
                 THEN 'customer_id ' || c.customer_id || ' reçu avec des contenus différents'
                 ELSE 'doublon exact de la ligne ' || (k.rang_premier + 1) || ' du fichier' END
FROM k
WHERE c.rang = k.rang
  AND (k.n_cle > k.n_identiques OR k.rang > k.rang_premier);

-- Intégration des lignes valides
INSERT INTO metier.customers (customer_id, customer_name, city)
SELECT customer_id, customer_name, city
FROM reception.customers_ctrl
WHERE regle IS NULL
ORDER BY customer_id;

-- Journal des rejets
INSERT INTO reception.rejets (source, rang, ligne_fichier, cle, regle, cause, contenu)
SELECT 'customers.csv', rang, rang + 1, customer_id_brut, regle, cause,
       jsonb_build_object('customer_id', customer_id_brut, 'customer_name', customer_name_brut,
                          'city', city_brut)
FROM reception.customers_ctrl
WHERE regle IS NOT NULL;
