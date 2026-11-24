-- Le mart doit avoir exactement une ligne par produit du catalogue.
-- Le test passe s'il ne renvoie aucune ligne.
select
    (select count(*) from {{ ref('mart_offres_produits') }}) as lignes_mart,
    (select count(*) from {{ source('metier', 'products') }}) as produits_catalogue
where (select count(*) from {{ ref('mart_offres_produits') }})
   <> (select count(*) from {{ source('metier', 'products') }})
