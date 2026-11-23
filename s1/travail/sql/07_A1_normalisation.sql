-- 07 : A1, table redondante (exemple des ateliers)
-- Tout est dans une transaction annulée à la fin : la base n'est pas modifiée.

BEGIN;

CREATE TEMP TABLE planning (
    reservation_id integer PRIMARY KEY,
    salle_id integer,
    salle_nom text,
    responsable text
);
\copy planning FROM '/s1/exemple/planning_a_normaliser.csv' WITH (FORMAT csv, HEADER true)

SELECT * FROM planning ORDER BY reservation_id;

-- Mise à jour : la salle 1 change de responsable, mais je ne modifie qu'une ligne
UPDATE planning SET responsable = 'Bruno' WHERE reservation_id = 1;
SELECT * FROM planning WHERE salle_id = 1 ORDER BY reservation_id;
-- Résultat : la salle 1 a deux responsables différents (Ariane et Bruno)

-- Insertion : impossible d'ajouter l'Atelier Photo sans réservation,
-- car reservation_id est la clé et ne peut pas être vide.
-- INSERT INTO planning VALUES (NULL, 3, 'Atelier Photo', 'Lina');  -> erreur

-- Suppression : je supprime la seule réservation de la salle 2
DELETE FROM planning WHERE reservation_id = 3;
SELECT * FROM planning WHERE salle_id = 2;
-- Résultat : plus aucune ligne, on a perdu le nom de la salle et sa responsable (Sam)

-- Solution : séparer les salles et les réservations
CREATE TEMP TABLE salles (
    salle_id integer PRIMARY KEY,
    nom text NOT NULL,
    responsable text
);
CREATE TEMP TABLE reservations (
    reservation_id integer PRIMARY KEY,
    salle_id integer NOT NULL REFERENCES salles(salle_id)
);

INSERT INTO salles VALUES (1, 'Atelier Céramique', 'Ariane'), (2, 'Atelier Textile', 'Sam');
INSERT INTO reservations VALUES (1, 1), (2, 1), (3, 2);

UPDATE salles SET responsable = 'Bruno' WHERE salle_id = 1;  -- une seule ligne à changer
INSERT INTO salles (salle_id, nom) VALUES (3, 'Atelier Photo'); -- possible sans réservation
DELETE FROM reservations WHERE reservation_id = 3;            -- la salle 2 existe toujours

SELECT * FROM salles ORDER BY salle_id;

-- Autre stratégie de jointure : INNER JOIN contre LEFT JOIN sur les clients NovaMarket
SELECT COUNT(DISTINCT c.customer_id) AS clients_inner_join
FROM metier.customers c
INNER JOIN metier.orders o ON o.customer_id = c.customer_id;

SELECT COUNT(DISTINCT c.customer_id) AS clients_left_join
FROM metier.customers c
LEFT JOIN metier.orders o ON o.customer_id = c.customer_id;
-- Le INNER JOIN fait disparaître les clients sans commande.

ROLLBACK;
