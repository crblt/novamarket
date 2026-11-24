-- Grain : un article dans une commande
select
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price_cents,
    quantity * unit_price_cents as montant_cents
from {{ source('metier', 'order_items') }}
