# NovaMarket – S1

Base PostgreSQL pour les fichiers NovaMarket : import, rejets, indicateurs et anomalies.
Les résultats et mes explications sont dans [RAPPORT.md](RAPPORT.md).

## Fichiers

| Fichier | Rôle |
| --- | --- |
| sql/01_tables.sql | crée les tables de réception et les tables métier |
| sql/02_import.sql | importe les CSV et le NDJSON |
| sql/03_integration.sql | envoie les bonnes lignes vers le métier et note les rejets |
| sql/04_controles.sql | compare lignes reçues / intégrées / rejetées |
| sql/tout_lancer.sql | lance 01 à 04 dans l'ordre |
| sql/05_indicateurs.sql | indicateurs (M3) |
| sql/06_anomalies.sql | anomalies (M4) |
| sql/07_A1_normalisation.sql | partie A1 (ne modifie pas la base) |

## Lancer

Depuis le dossier `novamarket/` :

```bash
docker compose up -d --wait postgres
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/tout_lancer.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/05_indicateurs.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/06_anomalies.sql
docker compose exec -T postgres psql -X -U atelier -d novamarket -f /s1/travail/sql/07_A1_normalisation.sql
```

`tout_lancer.sql` supprime et recrée les tables, donc on peut le relancer autant de fois qu'on veut.

Résultat attendu de `tout_lancer.sql` : 180 / 400 / 800 / 480 lignes intégrées et 2 rejets dans order_items.

## État du projet

- M1 à M4 : faits (voir RAPPORT.md)
- M5 : les contrôles se relancent avec `tout_lancer.sql`
- A1 : fait

## Limites

- Si un fichier contient une valeur du mauvais type (par exemple du texte dans une colonne de nombres), le `\copy` plante. Je n'ai pas géré ce cas car il n'arrive pas dans les fichiers fournis.
- Je ne sais pas si les paiements des commandes annulées ont été remboursés.
- Le catalogue produits n'est pas utilisé en S1.
- Sur Mac, il ne faut pas mettre le projet dans un dossier iCloud (Documents) : Docker n'arrive pas à lire les fichiers (`Input/output error`).

## Utilisation de l'IA

J'ai utilisé Claude pour m'aider à écrire les requêtes et à trouver les anomalies. J'ai lancé tous les scripts moi-même sur ma machine et vérifié que les chiffres étaient cohérents (reçues = intégrées + rejetées, encaissé = CA pour les commandes terminées).
