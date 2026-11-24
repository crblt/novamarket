-- Grain : une commande
select
    order_id,
    customer_id,
    ordered_on,
    status
from {{ source('metier', 'orders') }}
