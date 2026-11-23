-- Point d'entrée S1 : reconstruit reception + metier dans une seule transaction, puis contrôle.
-- Depuis novamarket/ :
--   docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket -f /s1/travail/sql/run_all.sql
-- En cas d'erreur, rien n'est validé : l'état précédent de la base est conservé.

\set ON_ERROR_STOP on
\pset footer off
SET client_min_messages = warning;

BEGIN;
\ir 00_schemas.sql
\ir 01_metier_ddl.sql
\ir 02_reception.sql
\ir 03_customers.sql
\ir 04_orders.sql
\ir 05_order_items.sql
\ir 06_payments.sql
\ir 07_vues.sql
ANALYZE metier.customers, metier.orders, metier.order_items, metier.payments;
\ir 08_bilan.sql
COMMIT;

\ir controles.sql
