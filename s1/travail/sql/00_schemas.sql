-- 00 · Schémas
-- Reconstruit entièrement la base S1 à chaque exécution (script idempotent).
-- reception : copie fidèle des fichiers (tout en text), tables de contrôle, journal des rejets.
-- metier    : données typées et contraintes, seules utilisées pour les indicateurs.
-- Attention : CASCADE supprime aussi les vues créées plus tard sur ces schémas.

DROP SCHEMA IF EXISTS metier CASCADE;
DROP SCHEMA IF EXISTS reception CASCADE;

CREATE SCHEMA reception;
CREATE SCHEMA metier;

COMMENT ON SCHEMA reception IS 'S1 · Réception brute des fichiers NovaMarket, contrôles et rejets';
COMMENT ON SCHEMA metier IS 'S1 · Données intégrées, typées et contraintes';
