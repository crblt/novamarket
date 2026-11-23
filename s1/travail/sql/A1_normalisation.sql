-- A1 · Anomalies d'insertion, de mise à jour et de suppression (exemple indépendant des ateliers)
--   docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket -f /s1/travail/sql/A1_normalisation.sql
-- Tables temporaires et ROLLBACK final : la base n'est pas modifiée.
-- Les erreurs attendues sont capturées dans des blocs DO pour que le script aille au bout.

\pset footer off
BEGIN;

-- ---------------------------------------------------------------------------
-- Partie 1 · Table redondante : le nom et le responsable de la salle sont répétés
--            à chaque réservation (dépendance salle_id -> salle_nom, responsable).
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE planning (
    reservation_id integer PRIMARY KEY,
    salle_id       integer NOT NULL,
    salle_nom      text    NOT NULL,
    responsable    text    NOT NULL
);
\copy planning (reservation_id, salle_id, salle_nom, responsable) FROM '/s1/exemple/planning_a_normaliser.csv' WITH (FORMAT csv, HEADER match)

\echo '== État initial =='
SELECT * FROM planning ORDER BY reservation_id;

\echo '== Anomalie de mise à jour : la salle 1 change de responsable, une seule ligne est modifiée =='
UPDATE planning SET responsable = 'Bruno' WHERE reservation_id = 1;
SELECT salle_id, string_agg(DISTINCT responsable, ' / ') AS responsables, count(DISTINCT responsable) AS versions
FROM planning GROUP BY salle_id ORDER BY salle_id;
-- La salle 1 a désormais deux responsables : aucune contrainte ne peut l'empêcher dans ce modèle.

\echo '== Anomalie d''insertion : déclarer l''Atelier Photo (salle 3) avant sa première réservation =='
DO $$
BEGIN
    INSERT INTO planning (reservation_id, salle_id, salle_nom, responsable)
    VALUES (NULL, 3, 'Atelier Photo', 'Lina');
EXCEPTION WHEN not_null_violation THEN
    RAISE INFO 'Insertion refusée : % (il faut inventer une réservation pour exister)', SQLERRM;
END
$$;

\echo '== Anomalie de suppression : annuler la dernière réservation de la salle 2 =='
DELETE FROM planning WHERE reservation_id = 3;
SELECT count(*) AS lignes_salle_2, string_agg(responsable, ', ') AS responsable_salle_2
FROM planning WHERE salle_id = 2;
-- Le nom « Atelier Textile » et sa responsable Sam ont disparu avec la réservation.

-- ---------------------------------------------------------------------------
-- Partie 2 · Forme normalisée : un fait = une table
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE salles_n (
    salle_id    integer PRIMARY KEY,
    nom         text NOT NULL,
    responsable text            -- peut rester inconnu tant que la salle n'est pas ouverte
);
CREATE TEMP TABLE reservations_n (
    reservation_id integer PRIMARY KEY,
    salle_id       integer NOT NULL REFERENCES salles_n (salle_id)
);

-- On repart du fichier d'origine (la partie 1 a altéré la table planning).
CREATE TEMP TABLE planning_origine (LIKE planning);
\copy planning_origine (reservation_id, salle_id, salle_nom, responsable) FROM '/s1/exemple/planning_a_normaliser.csv' WITH (FORMAT csv, HEADER match)

-- Une salle ne doit avoir qu'une version : on le vérifie AVANT le DISTINCT.
\echo '== Contrôle : une seule version (nom, responsable) par salle dans la source =='
SELECT salle_id, count(DISTINCT (salle_nom, responsable)) AS versions
FROM planning_origine GROUP BY salle_id ORDER BY salle_id;

INSERT INTO salles_n (salle_id, nom, responsable)
SELECT DISTINCT salle_id, salle_nom, responsable FROM planning_origine;
INSERT INTO reservations_n (reservation_id, salle_id)
SELECT reservation_id, salle_id FROM planning_origine;

\echo '== Les trois opérations ne posent plus de problème =='
UPDATE salles_n SET responsable = 'Bruno' WHERE salle_id = 1;          -- 1 ligne, une seule vérité
INSERT INTO salles_n (salle_id, nom) VALUES (3, 'Atelier Photo');        -- salle sans réservation
DELETE FROM reservations_n WHERE reservation_id = 3;                     -- la salle 2 reste connue

SELECT s.salle_id, s.nom, s.responsable, count(r.reservation_id) AS reservations
FROM salles_n AS s
LEFT JOIN reservations_n AS r ON r.salle_id = s.salle_id
GROUP BY s.salle_id, s.nom, s.responsable
ORDER BY s.salle_id;

\echo '== La clé étrangère protège désormais contre une réservation sur une salle inconnue =='
DO $$
BEGIN
    INSERT INTO reservations_n (reservation_id, salle_id) VALUES (4, 99);
EXCEPTION WHEN foreign_key_violation THEN
    RAISE INFO 'Insertion refusée : %', SQLERRM;
END
$$;

ROLLBACK;
