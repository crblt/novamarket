-- Indicateurs commerciaux (M3) · lecture seule, sur le schéma metier
--   docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/indicateurs.sql
-- Montants calculés en centimes ; la conversion en euros n'intervient qu'à l'affichage.

\pset footer off

\echo '== I1 · Commandes par statut =='
SELECT coalesce(status, 'TOTAL') AS statut,
       count(*)                  AS commandes,
       round(100.0 * count(*) / (SELECT count(*) FROM metier.orders), 1) AS pct
FROM metier.orders
GROUP BY ROLLUP (status)
ORDER BY status NULLS LAST;

\echo '== I2 · Clients sans commande =='
SELECT count(*) AS clients_total,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.customer_id = c.customer_id))
           AS clients_sans_commande,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM metier.orders o
                                          WHERE o.customer_id = c.customer_id AND o.status = 'completed'))
           AS clients_sans_commande_terminee
FROM metier.customers AS c;

\echo '-- détail : plage des identifiants sans commande'
SELECT min(customer_id) AS premier, max(customer_id) AS dernier, count(*) AS clients
FROM metier.customers AS c
WHERE NOT EXISTS (SELECT 1 FROM metier.orders AS o WHERE o.customer_id = c.customer_id);

\echo '== I3 · Montant des lignes des commandes terminées et panier moyen =='
-- Numérateur   : somme quantity x unit_price_cents des lignes des commandes status = completed.
-- Dénominateur : nombre de commandes terminées ayant au moins une ligne (une commande vide
--                ferait baisser le panier sans représenter d'achat). Ici les deux comptes coïncident.
SELECT count(*)                                   AS commandes_terminees,
       count(*) FILTER (WHERE nb_lignes > 0)      AS commandes_terminees_avec_lignes,
       sum(montant_lignes_cents)                  AS montant_lignes_cents,
       round(sum(montant_lignes_cents) / 100.0, 2) AS montant_lignes_eur,
       round(sum(montant_lignes_cents)::numeric / count(*) FILTER (WHERE nb_lignes > 0), 0) AS panier_moyen_cents,
       round(sum(montant_lignes_cents) / 100.0 / count(*) FILTER (WHERE nb_lignes > 0), 2)   AS panier_moyen_eur
FROM metier.v_commande_montant
WHERE status = 'completed';

\echo '-- vérification : même total calculé directement sur les lignes, sans la vue'
SELECT sum(i.quantity::bigint * i.unit_price_cents) AS montant_lignes_cents,
       count(DISTINCT i.order_id)                   AS commandes,
       count(*)                                     AS lignes
FROM metier.order_items AS i
JOIN metier.orders AS o ON o.order_id = i.order_id
WHERE o.status = 'completed';

\echo '-- panier moyen selon le dénominateur choisi (seul le premier correspond à la définition retenue)'
SELECT 'CA terminées / commandes terminées' AS definition,
       round(sum(montant_lignes_cents) FILTER (WHERE status = 'completed') / 100.0
             / count(*) FILTER (WHERE status = 'completed'), 2) AS panier_eur
FROM metier.v_commande_montant
UNION ALL
SELECT 'CA terminées / toutes commandes (faux : dénominateur hors périmètre)',
       round(sum(montant_lignes_cents) FILTER (WHERE status = 'completed') / 100.0 / count(*), 2)
FROM metier.v_commande_montant
UNION ALL
SELECT 'CA terminées / lignes terminées (prix moyen d''une ligne, pas un panier)',
       round(sum(montant_lignes_cents) FILTER (WHERE status = 'completed') / 100.0
             / sum(nb_lignes) FILTER (WHERE status = 'completed'), 2)
FROM metier.v_commande_montant;

\echo '== I4 · Montant des commandes terminées par mois de commande =='
SELECT date_trunc('month', ordered_on)::date       AS mois,
       count(*)                                    AS commandes_terminees,
       round(sum(montant_lignes_cents) / 100.0, 2) AS montant_lignes_eur,
       round(avg(montant_lignes_cents) / 100.0, 2) AS panier_moyen_eur
FROM metier.v_commande_montant
WHERE status = 'completed'
GROUP BY ROLLUP (date_trunc('month', ordered_on)::date)
ORDER BY mois NULLS LAST;

\echo '== I5 · Rapprochement commandé / payé, par statut de commande (grain commande) =='
SELECT coalesce(status, 'TOTAL')                       AS statut,
       count(*)                                        AS commandes,
       sum(nb_paiements)                               AS paiements,
       round(sum(montant_lignes_cents) / 100.0, 2)     AS commande_eur,
       round(sum(capture_cents) / 100.0, 2)            AS capture_eur,
       round(sum(attente_cents) / 100.0, 2)            AS en_attente_eur,
       round(sum(reste_a_capturer_cents) / 100.0, 2)   AS reste_a_capturer_eur,
       count(*) FILTER (WHERE ecart_total_cents <> 0)  AS commandes_ecart_total_non_nul
FROM metier.v_rapprochement
GROUP BY ROLLUP (status)
ORDER BY status NULLS LAST;

\echo '-- typologie des situations de paiement'
SELECT status AS statut_commande,
       CASE WHEN capture_cents = montant_lignes_cents AND attente_cents = 0 THEN 'intégralement capturée'
            WHEN capture_cents = 0 AND attente_cents = montant_lignes_cents THEN 'intégralement en attente'
            WHEN capture_cents + attente_cents = 0 THEN 'aucun paiement'
            WHEN capture_cents + attente_cents < montant_lignes_cents THEN 'sous-payée'
            WHEN capture_cents + attente_cents > montant_lignes_cents THEN 'sur-payée'
            ELSE 'mixte capturé / en attente' END AS situation,
       count(*) AS commandes,
       round(sum(capture_cents) / 100.0, 2) AS capture_eur
FROM metier.v_rapprochement
GROUP BY 1, 2
ORDER BY 1, 2;
