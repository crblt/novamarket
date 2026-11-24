with __dbt__cte__int_offres_par_produit as (
-- Grain : un produit qui a au moins une offre fournisseur
-- Je garde seulement la date d'observation la plus récente de chaque offre,
-- pour ne pas additionner deux fois le stock d'une offre vue deux jours de suite.
with dernieres_offres as (
    select o.*
    from "novamarket"."dbt_dev"."stg_offres" o
    where o.observed_on = (
        select max(o2.observed_on)
        from "novamarket"."dbt_dev"."stg_offres" o2
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
),  __dbt__cte__int_ventes_par_produit as (
-- Grain : un produit vendu (commandes terminées uniquement, comme le CA de S1)
select
    l.product_id,
    sum(l.quantity) as quantite_vendue,
    sum(l.montant_cents) as ca_cents
from "novamarket"."dbt_dev"."stg_lignes_commande" l
inner join "novamarket"."dbt_dev"."stg_commandes" c on c.order_id = l.order_id
where c.status = 'completed'
group by l.product_id
) -- Grain : un produit du catalogue (24 lignes)
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
from "novamarket"."dbt_dev"."stg_produits" p
left join __dbt__cte__int_offres_par_produit o on o.product_id = p.product_id
left join __dbt__cte__int_ventes_par_produit v on v.product_id = p.product_id