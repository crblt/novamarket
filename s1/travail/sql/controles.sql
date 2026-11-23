-- Contrôles essentiels (M5) · lecture seule, réexécutable à tout moment
--   docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket -f /s1/travail/sql/controles.sql
-- Un contrôle « bloquant » en échec fait échouer le script (code de sortie non nul).
-- Les volumes de référence correspondent aux fichiers S1 fournis le 23/11/2026 : à mettre à jour
-- si les sources changent.

\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP TABLE IF EXISTS pg_temp.controles;
CREATE TEMP TABLE controles AS
WITH ref(source, recues, integrees, rejetees) AS (
    VALUES ('customers.csv', 180, 180, 0),
           ('orders.csv', 400, 400, 0),
           ('order_items.csv', 802, 800, 2),
           ('payments.ndjson', 480, 480, 0)
)
-- C1 · chaque ligne reçue est intégrée ou rejetée avec une cause
SELECT 'C1' AS code, 'reçu = intégré + rejeté (' || b.source || ')' AS controle,
       '0' AS attendu, b.ecart_non_explique::text AS observe,
       b.ecart_non_explique = 0 AS ok, true AS bloquant
FROM reception.v_bilan_import AS b
UNION ALL
-- C2 · volumes identiques à la référence S1
SELECT 'C2', 'volumes de référence (' || b.source || ')',
       r.recues || '/' || r.integrees || '/' || r.rejetees,
       b.lignes_recues || '/' || b.lignes_integrees || '/' || b.lignes_rejetees,
       (b.lignes_recues, b.lignes_integrees, b.lignes_rejetees) = (r.recues, r.integrees, r.rejetees),
       false
FROM reception.v_bilan_import AS b
JOIN ref AS r USING (source)
UNION ALL
-- C3 · la vue au grain commande ne multiplie pas les montants de lignes
SELECT 'C3', 'somme lignes : vue commande = table order_items',
       (SELECT sum(quantity::bigint * unit_price_cents) FROM metier.order_items)::text,
       (SELECT sum(montant_lignes_cents) FROM metier.v_commande_montant)::text,
       (SELECT sum(quantity::bigint * unit_price_cents) FROM metier.order_items)
         = (SELECT sum(montant_lignes_cents) FROM metier.v_commande_montant),
       true
UNION ALL
-- C4 · idem pour les paiements
SELECT 'C4', 'somme paiements : vue rapprochement = table payments',
       (SELECT sum(amount_cents) FROM metier.payments)::text,
       (SELECT sum(capture_cents + attente_cents) FROM metier.v_rapprochement)::text,
       (SELECT sum(amount_cents) FROM metier.payments)
         = (SELECT sum(capture_cents + attente_cents) FROM metier.v_rapprochement),
       true
UNION ALL
-- C5 · le rapprochement garde une ligne par commande
SELECT 'C5', 'une ligne de rapprochement par commande',
       (SELECT count(*) FROM metier.orders)::text,
       (SELECT count(*) FROM metier.v_rapprochement)::text,
       (SELECT count(*) FROM metier.orders) = (SELECT count(*) FROM metier.v_rapprochement),
       true
UNION ALL
-- C6 · la répartition par statut couvre toutes les commandes
SELECT 'C6', 'somme des commandes par statut = total',
       (SELECT count(*) FROM metier.orders)::text,
       (SELECT sum(n) FROM (SELECT count(*) AS n FROM metier.orders GROUP BY status) AS s)::text,
       (SELECT count(*) FROM metier.orders)
         = (SELECT sum(n) FROM (SELECT count(*) AS n FROM metier.orders GROUP BY status) AS s),
       true
UNION ALL
-- C7 · aucune commande sans ligne d'article (sinon le panier moyen change de sens)
SELECT 'C7', 'commandes sans ligne d''article', '0',
       (SELECT count(*) FROM metier.v_commande_montant WHERE nb_lignes = 0)::text,
       (SELECT count(*) FROM metier.v_commande_montant WHERE nb_lignes = 0) = 0,
       false
UNION ALL
-- C8 · aucun rejet sans cause
SELECT 'C8', 'rejets sans règle ou sans cause', '0',
       (SELECT count(*) FROM reception.rejets WHERE coalesce(regle, '') = '' OR coalesce(cause, '') = '')::text,
       (SELECT count(*) FROM reception.rejets WHERE coalesce(regle, '') = '' OR coalesce(cause, '') = '') = 0,
       true;

\echo '== Contrôles essentiels =='
SELECT code, controle, attendu, observe,
       CASE WHEN ok THEN 'OK' WHEN bloquant THEN 'ÉCHEC' ELSE 'À EXAMINER' END AS statut
FROM controles
ORDER BY code, controle;

DO $$
DECLARE
    n integer;
BEGIN
    SELECT count(*) INTO n FROM pg_temp.controles WHERE bloquant AND NOT ok;
    IF n > 0 THEN
        RAISE EXCEPTION '% contrôle(s) bloquant(s) en échec', n;
    END IF;
    RAISE INFO 'Contrôles bloquants : tous OK';
END
$$;
