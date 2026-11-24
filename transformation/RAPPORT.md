# S4 – Chargement PostgreSQL et transformations dbt

Les 20 offres valides de S3 sont chargées dans le schéma `fournisseur` en une seule transaction, sans doublon au rejeu. Ensuite dbt construit 4 vues de staging, 2 modèles intermédiaires et un mart d'une ligne par produit. Les 11 tests passent.

## ETL ou ELT ?

Mon pipeline est un **ELT** :
- le programme Python **charge** les offres en contrôlant seulement le contrat (types, produit connu, unités, date, devise) ;
- les **transformations** analytiques sont faites ensuite **dans PostgreSQL** avec dbt.

Pourquoi ce choix :
- les données brutes restent dans la base, ce qui permet de retracer d'où vient chaque chiffre ;
- les règles d'analyse sont du SQL versionné, qu'on peut relancer et tester ;
- le volume est petit, donc pas besoin de transformer avant de charger.

## M1 – Chargement (`chargement_postgres.py`)

**Entrée** : `ingestion/data/valid/offres.jsonl`, qui contient 20 offres. Le fichier de secours `transformation/secours/offres.jsonl` est identique au mien.

**Tables créées dans le schéma `fournisseur`** (séparé de `metier`) :

| Table | Une ligne = | Clé |
| --- | --- | --- |
| `fournisseur.fournisseurs` | un fournisseur connu (F01, F02, F03 : liste du contrat de l'API S3) | `supplier_id` |
| `fournisseur.offres` | une offre observée à une date | `(offer_id, observed_on)` |
| `fournisseur.lots` | un lancement du chargement | `lot_id` |
| `fournisseur.rejets` | une ligne du fichier refusée | – |

- **La clé `(offer_id, observed_on)`** : la même offre peut être revue un autre jour sans créer de doublon, et sans écraser l'observation de la veille.
- **Les liens** : `product_id` référence `metier.products` et `supplier_id` référence `fournisseur.fournisseurs`. Un produit ou un fournisseur inconnu est donc refusé par le contrôle Python, et aussi par la base.

**Contrôles avant chargement** :
- champs obligatoires ;
- entiers pour `product_id`, `price_cents` et `available_units` ;
- prix et unités ≥ 0 ;
- devise EUR ;
- date valide ;
- produit présent dans le catalogue ;
- fournisseur présent dans le référentiel ;
- pas de doublon `(offer_id, observed_on)` dans le fichier.

Une ligne refusée va dans `fournisseur.rejets`, avec son numéro, sa cause et son contenu.

**Transaction** : tout le lot est dans `with connexion.transaction():`. Si une erreur arrive au milieu, PostgreSQL fait un ROLLBACK et **aucune** offre du lot ne reste. Le lot est quand même noté en `echec` dans `fournisseur.lots`.

**Idempotence (UPSERT)** : `INSERT … ON CONFLICT (offer_id, observed_on) DO UPDATE … WHERE … IS DISTINCT FROM …`. Si l'offre existe déjà avec les mêmes valeurs, rien n'est écrit et elle est comptée comme **inchangée** (ignorée). Si une valeur a changé, elle est **mise à jour**. Si elle est nouvelle, elle est **insérée**.

### Résultats

| Essai | Commande | Statut | Lues | Insérées | Mises à jour | Inchangées (ignorées) | Rejetées | Offres en base |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| panne simulée | `--simuler-panne 5` | échec (ROLLBACK) | 5 | 0 | 0 | 0 | 0 | 0 |
| 1er passage | sans option | succès | 20 | 20 | 0 | 0 | 0 | 20 |
| rejeu | sans option | succès | 20 | 0 | 0 | 20 | 0 | 20 |

- **Panne simulée** : 5 lignes avaient été écrites avant l'erreur. Après le ROLLBACK, la table est vide : il n'y a pas d'écriture partielle.
- **Rejeu** : il y a toujours 20 offres, et les 20 lignes sont reconnues comme déjà présentes. Relancer ne crée pas de doublons.

## M2 – Projet dbt

**dbt** lit des fichiers SQL (les *modèles*), remplace `{{ source() }}` et `{{ ref() }}` par les vrais noms de tables, trouve l'ordre d'exécution grâce à ces dépendances, puis exécute le SQL dans PostgreSQL. Il ne remplace ni l'API, ni le collecteur, ni le chargeur Python.

**Un seul projet** : `transformation/dbt/`, monté dans le conteneur sous `/projet`. Il contient :
- `dbt_project.yml` : le nom du projet, le profil et la matérialisation par dossier ;
- `models/staging/sources.yml` : les tables PostgreSQL d'entrée, déclarées avec `source()` (`fournisseur.offres`, `metier.products`, `metier.orders`, `metier.order_items`) ;
- le profil de connexion `s4/travail/profil/profiles.yml`, sans mot de passe écrit dedans : il est lu dans la variable `DBT_ENV_SECRET_PASSWORD`. Les modèles sont créés dans le schéma `dbt_dev`.

**Matérialisations** (fixées dans `dbt_project.yml`) :

| Dossier | Matérialisation | Ce que ça crée | Pourquoi |
| --- | --- | --- | --- |
| staging | `view` | une vue | légère, toujours à jour |
| intermediate | `ephemeral` | rien dans la base : le SQL est injecté dans le modèle suivant | étapes de calcul internes |
| marts | `table` | une table | résultat publié, rapide à lire |

## M3 – Staging

Le staging sert seulement à renommer, sélectionner et typer, sans logique métier.

| Modèle | Grain | Source |
| --- | --- | --- |
| `stg_offres` | une offre à une date | `fournisseur.offres` |
| `stg_produits` | un produit | `metier.products` |
| `stg_commandes` | une commande | `metier.orders` |
| `stg_lignes_commande` | un article d'une commande (+ `montant_cents`) | `metier.order_items` |

## M4 – Intermediate et premier mart

- `int_ventes_par_produit` (grain : un produit vendu) : quantité et CA des **commandes terminées** (même périmètre que le CA de S1).
- `int_offres_par_produit` (grain : un produit avec offre) : nombre d'offres, nombre de fournisseurs, prix minimum, unités disponibles. Pour chaque offre, je garde seulement sa date la plus récente, sinon le stock d'une offre vue deux jours serait compté deux fois.
- `mart_offres_produits` (grain : **un produit du catalogue**, 24 lignes) : catalogue `LEFT JOIN` offres `LEFT JOIN` ventes. Chaque côté est agrégé par produit **avant** la jointure, ce qui évite la multiplication des lignes vue en S1.

**Résultat** :
- 20 produits ont une offre et 4 n'en ont pas (produits 5, 10, 17 et 24, dont les offres ont été rejetées en S3 ou n'existaient pas) ;
- pour les 20 produits avec offre, le prix fournisseur est **égal** au prix de vente moyen NovaMarket, avec un écart de 0. Acheter à ces prix ne laisserait aucune marge : c'est à signaler au métier.

**SQL compilé** : `dbt compile` écrit la vraie requête dans `target/compiled/…/mart_offres_produits.sql`. On y voit que les modèles éphémères sont devenus des CTE `__dbt__cte__int_…` et que `{{ ref('stg_produits') }}` est devenu `"novamarket"."dbt_dev"."stg_produits"`.

## M5 – Vérifications

J'ai lancé `dbt compile` (génère le SQL sans rien exécuter), `dbt run` (construit les modèles) puis `dbt build` (construit les modèles **et** lance les tests dans l'ordre du graphe : 16 étapes au total). Les sorties sont gardées dans `transformation/resultats/`.
- **Tests génériques** (dans les `.yml`) : `unique` et `not_null` sur la clé de chaque modèle.
- **Tests SQL** (`tests/`), qui passent s'ils ne renvoient aucune ligne :

| Test | Ce qu'il vérifie |
| --- | --- |
| `mart_un_produit_par_ligne` | lignes du mart = produits du catalogue (24) |
| `mart_ca_egal_ca_s1` | CA total du mart = CA des commandes terminées de S1 (2 621 000 centimes) : pas de multiplication |
| `mart_offres_toutes_comptees` | somme des offres du mart = offres distinctes de la source (20) : aucune perdue |

Le graphe se lit avec `dbt ls --select +mart_offres_produits` (le `+` ajoute tous les modèles parents).

**Volumes** (`transformation/verifications.sql`) :

| Étape | Lignes | Explication |
| --- | --- | --- |
| `fournisseur.offres` (source) | 20 | les 20 offres valides |
| `dbt_dev.stg_offres` (staging) | 20 | même grain que la source, rien perdu |
| `dbt_dev.mart_offres_produits` (mart) | 24 | grain différent : un produit du catalogue. Les 20 offres concernent 20 produits, et les 4 produits sans offre sont gardés par le `LEFT JOIN` |

La somme des offres dans le mart vaut 20, comme la source, et le CA du mart vaut 2 621 000 centimes, comme en S1 : il n'y a pas de multiplication. L'écart 20 / 24 est donc attendu.

## Lancer

Depuis `novamarket/`, venv activé, PostgreSQL démarré, catalogue S2 chargé :

```bash
export NOVAMARKET_DSN="host=127.0.0.1 port=15432 dbname=novamarket user=atelier"
read -rs PGPASSWORD; export PGPASSWORD          # mot de passe local, jamais écrit dans un fichier
python transformation/exemple.py                 # exemple du kit (table temporaire)
python transformation/chargement_postgres.py --simuler-panne 5
python transformation/chargement_postgres.py     # 1er passage
python transformation/chargement_postgres.py     # rejeu

docker compose --profile transfo build dbt
export DBT_ENV_SECRET_PASSWORD="$PGPASSWORD"
export DBT_DATABASE=novamarket
docker compose --profile transfo run --rm --no-deps --user "$(id -u):$(id -g)" -w /projet \
  -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt dbt debug --profiles-dir /work/profil
# même commande en remplaçant « dbt debug » par « dbt compile », puis « dbt run », puis « dbt build »

docker compose exec -T postgres psql -X -U atelier -d novamarket < transformation/verifications.sql
```

## Limites

- Toutes les offres ont pour l'instant une seule date (2026-11-24). La clé et le modèle intermédiaire sont prévus pour plusieurs dates, mais le test `mart_offres_toutes_comptees` devra être adapté quand une offre aura plusieurs observations.
- Un produit présent dans le fichier mais absent du catalogue est rejeté. Si le catalogue change, il faut recharger S2 avant de relancer le chargement.
- `s1/travail/sql/tout_lancer.sql` supprime le schéma `metier` avec `CASCADE`. Il faudrait alors relancer S2, puis ce chargement, puis `dbt build`.
