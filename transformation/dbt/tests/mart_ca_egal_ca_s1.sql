-- Le CA total du mart doit être égal au CA des commandes terminées calculé en S1 (pas de multiplication).
select ca_mart, ca_s1
from (
    select
        (select sum(ca_cents) from {{ ref('mart_offres_produits') }}) as ca_mart,
        (select sum(i.quantity * i.unit_price_cents)
         from {{ source('metier', 'order_items') }} i
         inner join {{ source('metier', 'orders') }} o on o.order_id = i.order_id
         where o.status = 'completed') as ca_s1
) totaux
where ca_mart <> ca_s1
