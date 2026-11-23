-- S2 M2 : analyses avec fonctions de fenêtre et CTE
-- Périmètre : commandes terminées (completed) uniquement, comme le CA de S1.
-- Montants en centimes, affichés en euros.

-- 1. Classement des produits par CA (RANK)
-- La CTE donne une ligne par produit. Ensuite RANK classe sans regrouper.
-- RANK donne la même place aux ex æquo et saute la place suivante (1, 2, 2, 4).
WITH ca_produits AS (
    SELECT p.product_id, p.product_name, p.category_id,
           SUM(i.quantity * i.unit_price_cents) AS ca
    FROM metier.order_items i
    INNER JOIN metier.orders o ON o.order_id = i.order_id
    INNER JOIN metier.products p ON p.product_id = i.product_id
    WHERE o.status = 'completed'
    GROUP BY p.product_id, p.product_name, p.category_id
)
SELECT product_id, product_name, category_id,
       ROUND(ca / 100.0, 2) AS ca_euros,
       RANK() OVER (ORDER BY ca DESC) AS rang_global,
       RANK() OVER (PARTITION BY category_id ORDER BY ca DESC) AS rang_dans_categorie
FROM ca_produits
ORDER BY rang_global, product_id;

-- 2. Effet du doublon produit 3 sur le classement
-- Si je joins la table de réception (produit 3 en double) au lieu de metier.products,
-- les ventes du produit 3 sont comptées deux fois.
WITH ca_avec_doublon AS (
    SELECT p.product_id, SUM(i.quantity * i.unit_price_cents) AS ca
    FROM metier.order_items i
    INNER JOIN metier.orders o ON o.order_id = i.order_id
    INNER JOIN reception.products p ON p.product_id = i.product_id
    WHERE o.status = 'completed'
    GROUP BY p.product_id
),
classement AS (
    SELECT product_id, ca, RANK() OVER (ORDER BY ca DESC) AS rang
    FROM ca_avec_doublon
)
SELECT product_id, ROUND(ca / 100.0, 2) AS ca_euros_avec_doublon, rang AS rang_avec_doublon,
       (SELECT ROUND(SUM(ca) / 100.0, 2) FROM ca_avec_doublon) AS ca_total_avec_doublon
FROM classement
WHERE product_id = 3;

-- 3. Classement des clients par CA
WITH ca_clients AS (
    SELECT o.customer_id, SUM(i.quantity * i.unit_price_cents) AS ca
    FROM metier.orders o
    INNER JOIN metier.order_items i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id
)
SELECT customer_id, ROUND(ca / 100.0, 2) AS ca_euros,
       RANK() OVER (ORDER BY ca DESC) AS rang
FROM ca_clients
ORDER BY rang, customer_id
LIMIT 10;

-- 4. Evolution par mois (LAG et LEAD)
-- nb_jours montre si le mois est complet (novembre s'arrête au 19).
WITH ca_mois AS (
    SELECT date_trunc('month', o.ordered_on)::date AS mois,
           COUNT(DISTINCT o.ordered_on) AS nb_jours,
           MAX(o.ordered_on) AS dernier_jour,
           SUM(i.quantity * i.unit_price_cents) AS ca
    FROM metier.orders o
    INNER JOIN metier.order_items i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY date_trunc('month', o.ordered_on)::date
)
SELECT mois, nb_jours, dernier_jour,
       ROUND(ca / 100.0, 2) AS ca_euros,
       ROUND(LAG(ca) OVER (ORDER BY mois) / 100.0, 2) AS ca_mois_precedent,
       ROUND((ca - LAG(ca) OVER (ORDER BY mois)) / 100.0, 2) AS evolution_euros,
       ROUND(LEAD(ca) OVER (ORDER BY mois) / 100.0, 2) AS ca_mois_suivant,
       ROUND(ca / 100.0 / nb_jours, 2) AS ca_moyen_par_jour
FROM ca_mois
ORDER BY mois;

-- 5. Segmentation des clients en 4 groupes (NTILE)
-- Population : les clients qui ont au moins une commande terminée.
-- Tri : CA décroissant, puis customer_id pour que le résultat soit toujours le même.
WITH ca_clients AS (
    SELECT o.customer_id, SUM(i.quantity * i.unit_price_cents) AS ca
    FROM metier.orders o
    INNER JOIN metier.order_items i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id
),
segments AS (
    SELECT customer_id, ca,
           NTILE(4) OVER (ORDER BY ca DESC, customer_id) AS quartile
    FROM ca_clients
)
SELECT quartile, COUNT(*) AS nb_clients,
       ROUND(MIN(ca) / 100.0, 2) AS ca_min_euros,
       ROUND(MAX(ca) / 100.0, 2) AS ca_max_euros,
       ROUND(SUM(ca) / 100.0, 2) AS ca_total_euros
FROM segments
GROUP BY quartile
ORDER BY quartile;

-- 6. Hiérarchie des catégories (WITH RECURSIVE)
-- Ancre : les catégories sans parent. Ensuite on descend niveau par niveau.
-- Condition d'arrêt : profondeur < 10, pour ne pas boucler s'il y avait un cycle.
WITH RECURSIVE arbre AS (
    SELECT category_id, category_name, parent_category_id,
           category_id AS racine_id, 0 AS profondeur,
           category_name AS chemin
    FROM metier.categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_name, c.parent_category_id,
           a.racine_id, a.profondeur + 1,
           a.chemin || ' > ' || c.category_name
    FROM metier.categories c
    INNER JOIN arbre a ON c.parent_category_id = a.category_id
    WHERE a.profondeur < 10
)
SELECT category_id, profondeur, chemin
FROM arbre
ORDER BY chemin;

-- Contrôle : toutes les catégories sont atteintes une seule fois (sinon cycle ou rattachement manquant)
WITH RECURSIVE arbre AS (
    SELECT category_id, 0 AS profondeur
    FROM metier.categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, a.profondeur + 1
    FROM metier.categories c
    INNER JOIN arbre a ON c.parent_category_id = a.category_id
    WHERE a.profondeur < 10
)
SELECT (SELECT COUNT(*) FROM metier.categories) AS nb_categories,
       COUNT(*) AS nb_lignes_arbre,
       COUNT(DISTINCT category_id) AS nb_categories_atteintes
FROM arbre;

-- 7. CA par famille (catégorie racine)
-- Chaque produit est rattaché à une seule catégorie, donc il est compté une seule fois dans sa famille.
WITH RECURSIVE arbre AS (
    SELECT category_id, category_id AS racine_id, category_name AS famille, 0 AS profondeur
    FROM metier.categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, a.racine_id, a.famille, a.profondeur + 1
    FROM metier.categories c
    INNER JOIN arbre a ON c.parent_category_id = a.category_id
    WHERE a.profondeur < 10
)
SELECT a.famille,
       COUNT(DISTINCT p.product_id) AS nb_produits,
       ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2) AS ca_euros
FROM metier.order_items i
INNER JOIN metier.orders o ON o.order_id = i.order_id
INNER JOIN metier.products p ON p.product_id = i.product_id
INNER JOIN arbre a ON a.category_id = p.category_id
WHERE o.status = 'completed'
GROUP BY a.famille
ORDER BY ca_euros DESC;
