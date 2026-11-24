-- Grain : un produit qui a au moins une offre fournisseur
-- Je garde seulement la date d'observation la plus récente de chaque offre,
-- pour ne pas additionner deux fois le stock d'une offre vue deux jours de suite.
with dernieres_offres as (
    select o.*
    from {{ ref('stg_offres') }} o
    where o.observed_on = (
        select max(o2.observed_on)
        from {{ ref('stg_offres') }} o2
        where o2.offer_id = o.offer_id
    )
)

select
    product_id,
    count(*) as nb_offres,
    count(distinct supplier_id) as nb_fournisseurs,
    min(price_cents) as prix_offre_min_cents,
    sum(available_units) as unites_disponibles,
    max(observed_on) as derniere_observation
from dernieres_offres
group by product_id
