-- S2 M1 : intégration du catalogue (catégories et produits)
-- A lancer après le S1 (s1/travail/sql/tout_lancer.sql).
-- Avant : copier les fichiers dans le conteneur (voir README).

\set ON_ERROR_STOP on
BEGIN;

-- Pour pouvoir relancer le script
DROP TABLE IF EXISTS reception.categories;
DROP TABLE IF EXISTS reception.products;
DROP TABLE IF EXISTS metier.products CASCADE;
DROP TABLE IF EXISTS metier.categories CASCADE;
DELETE FROM reception.rejets WHERE fichier IN ('categories.csv', 'products.csv');

-- Réception (sans clé, comme en S1)
CREATE TABLE reception.categories (
    category_id integer,
    category_name text,
    parent_category_id integer
);

CREATE TABLE reception.products (
    product_id integer,
    sku text,
    product_name text,
    category_id integer,
    first_listed_on date
);

\copy reception.categories FROM '/tmp/novamarket-s2/categories.csv' WITH (FORMAT csv, HEADER true)
\copy reception.products FROM '/tmp/novamarket-s2/products.csv' WITH (FORMAT csv, HEADER true)

-- Tables métier
CREATE TABLE metier.categories (
    category_id integer PRIMARY KEY,
    category_name text NOT NULL,
    parent_category_id integer REFERENCES metier.categories(category_id) -- vide = catégorie racine
);

CREATE TABLE metier.products (
    product_id integer PRIMARY KEY,
    sku text NOT NULL UNIQUE,
    product_name text NOT NULL,
    category_id integer NOT NULL REFERENCES metier.categories(category_id),
    first_listed_on date NOT NULL
);

-- Catégories : doublons, puis intégration si le parent existe
INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT 'categories.csv', category_id, 'doublon exact', COUNT(*) - 1
FROM reception.categories
GROUP BY category_id, category_name, parent_category_id
HAVING COUNT(*) > 1;

INSERT INTO metier.categories (category_id, category_name, parent_category_id)
SELECT DISTINCT c.category_id, c.category_name, c.parent_category_id
FROM reception.categories c
WHERE c.parent_category_id IS NULL
   OR EXISTS (SELECT 1 FROM reception.categories p WHERE p.category_id = c.parent_category_id);

INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT DISTINCT 'categories.csv', c.category_id, 'parent inexistant : ' || c.parent_category_id, 1
FROM reception.categories c
WHERE c.parent_category_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM reception.categories p WHERE p.category_id = c.parent_category_id);

-- Produits : doublons, puis intégration si la catégorie existe
INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT 'products.csv', product_id, 'doublon exact', COUNT(*) - 1
FROM reception.products
GROUP BY product_id, sku, product_name, category_id, first_listed_on
HAVING COUNT(*) > 1;

INSERT INTO metier.products (product_id, sku, product_name, category_id, first_listed_on)
SELECT DISTINCT p.product_id, p.sku, p.product_name, p.category_id, p.first_listed_on
FROM reception.products p
WHERE EXISTS (SELECT 1 FROM metier.categories c WHERE c.category_id = p.category_id);

INSERT INTO reception.rejets (fichier, identifiant, raison, nb_lignes)
SELECT DISTINCT 'products.csv', p.product_id, 'catégorie inexistante : ' || p.category_id, 1
FROM reception.products p
WHERE NOT EXISTS (SELECT 1 FROM metier.categories c WHERE c.category_id = p.category_id);

-- Comptages
SELECT 'categories.csv' AS fichier,
       (SELECT COUNT(*) FROM reception.categories) AS recues,
       (SELECT COUNT(*) FROM metier.categories) AS integrees,
       (SELECT COALESCE(SUM(nb_lignes), 0) FROM reception.rejets WHERE fichier = 'categories.csv') AS rejetees
UNION ALL
SELECT 'products.csv',
       (SELECT COUNT(*) FROM reception.products),
       (SELECT COUNT(*) FROM metier.products),
       (SELECT COALESCE(SUM(nb_lignes), 0) FROM reception.rejets WHERE fichier = 'products.csv');

SELECT * FROM reception.rejets WHERE fichier IN ('categories.csv', 'products.csv');

-- Lien avec les ventes S1 : produits vendus absents du catalogue (doit être vide)
SELECT DISTINCT i.product_id
FROM metier.order_items i
WHERE NOT EXISTS (SELECT 1 FROM metier.products p WHERE p.product_id = i.product_id);

-- Tous les produits vendus sont dans le catalogue, donc j'ajoute la clé étrangère
ALTER TABLE metier.order_items
    ADD CONSTRAINT order_items_product_fk FOREIGN KEY (product_id) REFERENCES metier.products(product_id);

-- Produits du catalogue jamais vendus
SELECT p.product_id, p.product_name
FROM metier.products p
WHERE NOT EXISTS (SELECT 1 FROM metier.order_items i WHERE i.product_id = p.product_id);

-- Lignes vendues avant la date de mise en vente du produit
SELECT p.product_id, p.first_listed_on, o.order_id, o.ordered_on, o.status
FROM metier.order_items i
INNER JOIN metier.orders o ON o.order_id = i.order_id
INNER JOIN metier.products p ON p.product_id = i.product_id
WHERE o.ordered_on < p.first_listed_on
ORDER BY o.ordered_on;

COMMIT;
