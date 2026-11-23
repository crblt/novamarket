-- 07 · Vues au grain commande, réutilisables pour les indicateurs (S1) et la BI (S6)
-- Règle : on agrège chaque table enfant à son niveau AVANT de la rapprocher d'une autre.
-- Joindre directement order_items et payments produirait n_lignes x n_paiements lignes par commande.

-- Montant des lignes par commande (toutes les commandes, même sans ligne)
CREATE VIEW metier.v_commande_montant AS
SELECT o.order_id,
       o.customer_id,
       o.ordered_on,
       o.status,
       coalesce(l.nb_lignes, 0)            AS nb_lignes,
       coalesce(l.montant_lignes_cents, 0) AS montant_lignes_cents
FROM metier.orders AS o
LEFT JOIN (
    SELECT order_id,
           count(*)                                   AS nb_lignes,
           sum(quantity::bigint * unit_price_cents)   AS montant_lignes_cents
    FROM metier.order_items
    GROUP BY order_id
) AS l ON l.order_id = o.order_id;

-- Paiements par commande, séparés par état
CREATE VIEW metier.v_commande_paiement AS
SELECT o.order_id,
       count(p.payment_id)                                               AS nb_paiements,
       coalesce(sum(p.amount_cents) FILTER (WHERE p.status = 'captured'), 0) AS capture_cents,
       coalesce(sum(p.amount_cents) FILTER (WHERE p.status = 'pending'), 0)  AS attente_cents
FROM metier.orders AS o
LEFT JOIN metier.payments AS p ON p.order_id = o.order_id
GROUP BY o.order_id;

-- Rapprochement commandé / payé : une ligne par commande, grains déjà alignés
CREATE VIEW metier.v_rapprochement AS
SELECT m.order_id,
       m.customer_id,
       m.ordered_on,
       m.status,
       m.nb_lignes,
       p.nb_paiements,
       m.montant_lignes_cents,
       p.capture_cents,
       p.attente_cents,
       m.montant_lignes_cents - p.capture_cents                   AS reste_a_capturer_cents,
       m.montant_lignes_cents - p.capture_cents - p.attente_cents AS ecart_total_cents
FROM metier.v_commande_montant AS m
JOIN metier.v_commande_paiement AS p ON p.order_id = m.order_id;

COMMENT ON VIEW metier.v_commande_montant  IS 'Grain commande · montant des lignes en centimes';
COMMENT ON VIEW metier.v_commande_paiement IS 'Grain commande · paiements capturés / en attente en centimes';
COMMENT ON VIEW metier.v_rapprochement     IS 'Grain commande · commandé vs payé, sans multiplication des lignes';
