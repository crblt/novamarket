-- Toutes les offres de la source doivent se retrouver dans le mart (aucune perdue, aucune comptée deux fois).
-- Valable tant que chaque offre n'a qu'une date d'observation.
select nb_mart, nb_source
from (
    select
        (select sum(nb_offres) from {{ ref('mart_offres_produits') }}) as nb_mart,
        (select count(distinct offer_id) from {{ source('fournisseur', 'offres') }}) as nb_source
) totaux
where nb_mart <> nb_source
