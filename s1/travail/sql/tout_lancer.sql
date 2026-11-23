-- Lance tout l'import dans l'ordre. Si une étape plante, rien n'est enregistré (ROLLBACK automatique).
\set ON_ERROR_STOP on

BEGIN;
\i /s1/travail/sql/01_tables.sql
\i /s1/travail/sql/02_import.sql
\i /s1/travail/sql/03_integration.sql
COMMIT;

\i /s1/travail/sql/04_controles.sql
