-- Grain : un produit du catalogue (24 lignes)
-- Compare la meilleure offre fournisseur au prix de vente moyen NovaMarket.
-- LEFT JOIN : on garde les produits sans offre ou sans vente.
select
    p.product_id,
    p.product_name,
    p.category_id,
    coalesce(o.nb_offres, 0) as nb_offres,
    o.prix_offre_min_cents,
    coalesce(o.unites_disponibles, 0) as unites_disponibles,
    coalesce(v.quantite_vendue, 0) as quantite_vendue,
    coalesce(v.ca_cents, 0) as ca_cents,
    round(v.ca_cents::numeric / v.quantite_vendue) as prix_moyen_vente_cents,
    round(v.ca_cents::numeric / v.quantite_vendue) - o.prix_offre_min_cents as ecart_vente_offre_cents
from {{ ref('stg_produits') }} p
left join {{ ref('int_offres_par_produit') }} o on o.product_id = p.product_id
left join {{ ref('int_ventes_par_produit') }} v on v.product_id = p.product_id
