# NovaMarket S1 et S2

Base PostgreSQL NovaMarket : import des ventes (S1), catalogue et analyses (S2), benchmark et index (dossier s3/), puis collecte asynchrone des offres fournisseurs (séance S3, dossier ingestion/).

| Dossier | Contenu |
| --- | --- |
| s1/travail | tables, import, rejets, indicateurs et anomalies (voir son README et son RAPPORT) |
| s2/travail | catalogue, classements, évolution, segmentation, hiérarchie (RAPPORT.md) |
| s3/travail | benchmark : mesures avant / après index (RAPPORT.md et resultats/) |
| ingestion | séance S3 : collecteur Python asynchrone de l'API fournisseur (CONTRAT.md et RAPPORT.md) |

Les fichiers fournis (`s1/donnees`, `s2/donnees`, `s3/generer.sql`) ne sont pas modifiés.

## Tout relancer dans l'ordre

Depuis le dossier `novamarket/` :

```bash
docker compose up -d --wait postgres

# S1 : ventes
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/tout_lancer.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/05_indicateurs.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/06_anomalies.sql

# S2 : copier les CSV dans le conteneur, puis catalogue et analyses
docker compose exec -T postgres mkdir -p /tmp/novamarket-s2
docker compose cp s2/donnees/. postgres:/tmp/novamarket-s2/
docker compose exec -T postgres psql -X -U atelier -d novamarket < s2/travail/sql/01_catalogue.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket < s2/travail/sql/02_analyses.sql

# S3 : benchmark (la génération ne se fait qu'une fois)
mkdir -p s3/travail/resultats
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s3/generer.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket < s3/travail/sql/01_verif.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket < s3/travail/sql/02_mesures.sql > s3/travail/resultats/avant_index.txt
docker compose exec -T postgres psql -X -U atelier -d novamarket < s3/travail/sql/03_index.sql > s3/travail/resultats/index.txt
docker compose exec -T postgres psql -X -U atelier -d novamarket < s3/travail/sql/02_mesures.sql > s3/travail/resultats/apres_index.txt
docker compose exec -T postgres psql -X -U atelier -d novamarket < s3/travail/sql/04_jointure_estimations.sql > s3/travail/resultats/jointure_estimations.txt
```

`s1/travail/sql/tout_lancer.sql` recrée les tables de S1. ensuite il faut relancer `01_catalogue.sql` de S2

Pour refaire les mesures « avant index » une deuxième fois, il faut d'abord supprimer l'index : `DROP INDEX benchmark.benchmark_sales_store_idx;`

## Ingestion (séance S3)

Python 3.12 et Docker Desktop. Depuis `novamarket/` :

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-v3.txt
docker compose up -d --build --wait fournisseur
python ingestion/src/collecteur.py --scenario atelier --run atelier01
```

Le détail est dans `ingestion/RAPPORT.md`. Les offres valides sont dans `ingestion/data/valid/offres.jsonl` (entrée de S4).

## Chargement PostgreSQL et dbt (séance S4)

Depuis `novamarket/`, venv activé, PostgreSQL démarré et catalogue S2 chargé :

```bash
export NOVAMARKET_DSN="host=127.0.0.1 port=15432 dbname=novamarket user=atelier"
read -rs PGPASSWORD; export PGPASSWORD
python transformation/chargement_postgres.py
export DBT_ENV_SECRET_PASSWORD="$PGPASSWORD" DBT_DATABASE=novamarket
mkdir -p s4/travail/profil && cp transformation/dbt/profiles.exemple.yml s4/travail/profil/profiles.yml
docker compose --profile transfo build dbt
docker compose --profile transfo run --rm --no-deps --user "$(id -u):$(id -g)" -w /projet -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt dbt build --profiles-dir /work/profil
```

Détails, résultats et limites : `transformation/RAPPORT.md`. Preuves : `transformation/resultats/`.
`s4/` est le dossier du kit (Dockerfile de l'image dbt, exemple indépendant). `s4/travail/` est ignoré par Git : le profil dbt se recrée avec la commande `cp` ci-dessus.
Limite principale : relancer `s1/travail/sql/tout_lancer.sql` recrée le schéma `metier`, il faut ensuite relancer S2, ce chargement, puis `dbt build`.
