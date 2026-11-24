-- Grain : un produit vendu (commandes terminées uniquement, comme le CA de S1)
select
    l.product_id,
    sum(l.quantity) as quantite_vendue,
    sum(l.montant_cents) as ca_cents
from {{ ref('stg_lignes_commande') }} l
inner join {{ ref('stg_commandes') }} c on c.order_id = l.order_id
where c.status = 'completed'
group by l.product_id
