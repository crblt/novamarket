-- Grain : un produit du catalogue
select
    product_id,
    sku,
    product_name,
    category_id,
    first_listed_on
from {{ source('metier', 'products') }}
