-- Grain : une offre fournisseur à une date
select
    offer_id,
    observed_on,
    supplier_id,
    product_id,
    price_cents,
    available_units,
    lot_id
from {{ source('fournisseur', 'offres') }}
where currency = 'EUR'
