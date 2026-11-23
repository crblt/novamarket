# NovaMarket · S1 — Base relationnelle, rejets tracés et premiers indicateurs

Dossier de travail de la séance S1 (lundi 23 novembre 2026), dans le dépôt commun `novamarket/`. Il est conservé pour la note collective n°1 et sert de base aux séances suivantes.

## Contenu

```
s1/travail/
├── README.md                  ce fichier
├── capturer_resultats.sh      rejoue tout et écrit les sorties dans docs/resultats/
├── sql/
│   ├── run_all.sql            point d'entrée : 00 → 08 dans une transaction, puis controles.sql
│   ├── 00_schemas.sql         schémas reception et metier (reconstruits à chaque exécution)
│   ├── 01_metier_ddl.sql      tables métier : types, PK, FK, CHECK
│   ├── 02_reception.sql       tables brutes en text, journal des rejets, \copy CSV et NDJSON
│   ├── 03_customers.sql       contrôle R1–R6, intégration, rejets
│   ├── 04_orders.sql          idem
│   ├── 05_order_items.sql     idem
│   ├── 06_payments.sql        idem + R0 (JSON invalide)
│   ├── 07_vues.sql            vues au grain commande (montants, paiements, rapprochement)
│   ├── 08_bilan.sql           bilan reçu / intégré / rejeté et journal des rejets
│   ├── controles.sql          M5 : contrôles essentiels, échoue si un contrôle bloquant échoue
│   ├── indicateurs.sql        M3 : statuts, clients sans commande, CA, panier, rapprochement
│   ├── anomalies.sql          M4 : doublons, orphelins, multiplication, impact du statut
│   ├── A1_normalisation.sql   A1 : anomalies d'insertion / mise à jour / suppression (ROLLBACK)
│   └── A1_jointures.sql       A1 : cinq stratégies de jointure comparées
└── docs/
    ├── SCHEMA.md              M1 : grain, schéma annoté (Mermaid), règles de rejet, choix justifiés
    ├── INDICATEURS.md         M3 : résultats, hypothèses, vérifications
    ├── ANOMALIES.md           M4 : tableau anomalie / détection / effet / décision
    ├── NOTE_A1.md             A1 : note complémentaire
    └── resultats/             sorties psql + rejets.csv
```

Les fichiers bruts de `s1/donnees/` ne sont jamais modifiés : le répertoire `s1/` est monté en lecture seule dans le conteneur, sous `/s1`.

## Exécuter

Prérequis : Docker et Compose (voir `s1/DEMARRAGE.md`). Toutes les commandes se lancent **depuis `novamarket/`**.

```bash
docker compose up -d --wait postgres

# 1. Construire la base (réception, contrôles, intégration, vues) puis lancer les contrôles
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket -f /s1/travail/sql/run_all.sql

# 2. Indicateurs et anomalies (lecture seule, relançables à volonté)
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/indicateurs.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/anomalies.sql

# 3. Approfondissement (ne modifie pas la base)
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket -f /s1/travail/sql/A1_normalisation.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/A1_jointures.sql

# Tout rejouer et régénérer les preuves dans docs/resultats/
bash s1/travail/capturer_resultats.sh

# Réexécuter seulement les contrôles essentiels
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket -f /s1/travail/sql/controles.sql
```

`run_all.sql` est **idempotent** : il supprime et recrée les schémas `reception` et `metier`. Tout s'exécute dans une transaction ; en cas d'erreur, rien n'est validé et la base garde son état précédent. Durée : environ une seconde.

## Résultat attendu

| Source | Reçues | Intégrées | Rejetées | Cause des rejets |
| --- | ---: | ---: | ---: | --- |
| `customers.csv` | 180 | 180 | 0 | |
| `orders.csv` | 400 | 400 | 0 | |
| `order_items.csv` | 802 | 800 | 2 | ligne 802 : doublon exact de la ligne 8 (R4) ; ligne 803 : commande 9999 inconnue (R6) |
| `payments.ndjson` | 480 | 480 | 0 | |

Principaux indicateurs : 320 commandes terminées / 40 en attente / 40 annulées ; 30 clients sans commande ; CA des commandes terminées **26 210,00 €** ; panier moyen **81,91 €** (÷ 320 commandes terminées) ; aucun écart commandé / payé au grain commande, mais 3 283,75 € capturés sur les 40 commandes annulées.

Les 14 contrôles de `controles.sql` doivent tous afficher `OK` (C1 à C8).

## État du projet (S1, 23/11/2026)

| Livrable | État |
| --- | --- |
| M1 schéma annoté et choix justifiés | fait : `docs/SCHEMA.md` |
| M2 DDL, imports CSV / NDJSON, comptages, journal des rejets | fait : `sql/00`–`08`, `reception.rejets`, `docs/resultats/rejets.csv` |
| M3 indicateurs, hypothèses, vérifications | fait : `sql/indicateurs.sql`, `docs/INDICATEURS.md` |
| M4 tableau d'anomalies | fait : `sql/anomalies.sql`, `docs/ANOMALIES.md` |
| M5 contrôles réexécutables, README | fait : `sql/controles.sql`, ce fichier |
| A1 normalisation et jointures | fait : `sql/A1_*.sql`, `docs/NOTE_A1.md` |

**Validé le 23/11/2026** avec le kit (PostgreSQL 17.12, Docker Desktop 4.99, macOS Apple Silicon) : bilan, 14 contrôles `OK`, indicateurs et anomalies identiques aux sorties de `docs/resultats/`. Les règles R0–R6 ont aussi été testées sur un jeu volontairement dégradé (une ou plusieurs lignes par règle). Versions minimales : PostgreSQL 16 (`pg_input_is_valid`), `HEADER match` depuis la 15.

## Dépannage

| Symptôme | Cause | Action |
| --- | --- | --- |
| `could not read from input file: Input/output error` alors que `ls /s1/...` fonctionne | Projet placé dans un dossier synchronisé par iCloud (Documents, Bureau) : Docker liste les fichiers mais ne peut pas toujours les lire. | `docker compose down`, copier le projet hors iCloud (ex. `~/novamarket`), relancer depuis ce dossier. |
| `Unable to find application named 'Docker'` | Docker Desktop non installé. | Installer Docker Desktop (Apple Silicon ou Intel selon `uname -m`). |
| `zsh: permission denied: /chemin/du/dossier` | Chemin tapé sans `cd` devant. | `cd "/chemin/du/dossier"`. |
| Un contrôle bloquant en `ÉCHEC` | Données métier modifiées à la main ou fichiers sources changés. | Relancer `run_all.sql` ; si l'échec persiste, lire le bilan et `reception.rejets`. |

## Limites connues

- **Volumes de référence figés** : le contrôle C2 compare aux volumes des fichiers du 23/11/2026 ; il passe en « À EXAMINER » (non bloquant) si les sources changent.
- **Remboursements absents** : les sources ne permettent pas de savoir si les 3 283,75 € capturés sur commandes annulées ont été remboursés. Hypothèse à confirmer avec le métier.
- **Catalogue hors périmètre** : pas de clé étrangère vers `products` ; `products.csv` contient un doublon (produit 3) et une date de référencement postérieure à des ventes (produit 6), à traiter lors de son intégration.
- **Reconstruction destructive** : `00_schemas.sql` supprime `reception` et `metier` avec `CASCADE`. Des vues créées plus tard au-dessus (dbt, Metabase) seraient supprimées : les placer dans d'autres schémas et reconstruire dans l'ordre.
- **Pas d'index sur les clés étrangères** : choix volontaire, laissé à la séance S3.
- **Ordre des lignes** : le numéro de ligne (`rang`) repose sur l'ordre d'insertion de `\copy`, séquentiel pour un fichier chargé en une fois.

## Déposer

Dépôt GitHub **privé**, depuis `novamarket/` :

```bash
git add .
git commit -m "S1 : schéma, import tracé, indicateurs et anomalies"
git push
```

Le `.gitignore` à la racine exclut les fichiers temporaires de Word (`~$*`) et de macOS (`.DS_Store`). Noter le hash du commit (`git log -1 --format=%h`) dans le rendu.
