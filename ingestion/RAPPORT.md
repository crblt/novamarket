# S3 – Ingestion asynchrone : mode d'emploi et bilan

Le contrat de l'API est dans [CONTRAT.md](CONTRAT.md).

## Fichiers

| Fichier | Rôle |
| --- | --- |
| src/collecteur.py | collecte des 6 pages avec aiohttp (concurrence bornée, reprises), écrit raw / valid / rejected |
| src/validation.py | règles de contrôle d'une offre et motif de rejet |
| src/journalisation.py | logs (écran + fichier) et écriture des JSONL et du bilan |
| tests/test_validation.py | petits tests des règles, sans API |
| data/raw/ | `<scenario>_<run>.jsonl` : toutes les réponses reçues, essais ratés compris |
| data/valid/offres.jsonl | les offres valides de la dernière collecte **complète** |
| data/rejected/ | `<scenario>_<run>.jsonl` : page, position, motif et offre brute |
| logs/ | `<scenario>_<run>.log` et `<scenario>_<run>_bilan.json` |

## Lancer

Depuis `novamarket/` :

```bash
source .venv/bin/activate
docker compose up -d --build --wait fournisseur
python ingestion/tests/disponibilite.py
python ingestion/tests/test_validation.py
python ingestion/src/collecteur.py --scenario clean --run clean01
python ingestion/src/collecteur.py --scenario clean --run seq01 --sequentiel
python ingestion/src/collecteur.py --scenario atelier --run atelier01
python ingestion/src/collecteur.py --scenario panne --run panne01
```

Options : `--concurrence N` (3 par défaut), `--sequentiel` (une page à la fois). Il faut changer de `--run` pour revoir les erreurs de la première tentative.

## Mes choix

- **Concurrence bornée** : un `asyncio.Semaphore(3)` autour de l'appel HTTP, donc au plus 3 requêtes en même temps. Le bilan affiche le maximum réellement observé.
- **Une seule `ClientSession`** pour toutes les pages, avec un timeout de 1 s par requête.
- **Reprises** : au plus 3 tentatives par page, uniquement pour les erreurs qui peuvent passer (429, 5xx, timeout, erreur réseau, JSON invalide). J'attends `Retry-After` quand l'API le donne (5 s maximum), sinon 0,5 s puis 1 s. L'attente se fait en dehors du sémaphore pour ne pas bloquer les autres pages. Une erreur 400 ou 404 n'est pas réessayée.
- **Lot incomplet** : si une page manque après ses 3 tentatives, la collecte est en échec. Rien n'est écrit dans `valid/` et le programme se termine avec le code 1. On garde quand même le raw, le log et le bilan pour comprendre.
- **Validation** : champs obligatoires, types, prix et unités ≥ 0, devise EUR, date ISO, produit présent dans le catalogue S2, pas de doublon d'`offer_id`. Les offres sont contrôlées dans l'ordre des pages, donc en cas de doublon c'est toujours la première qui est gardée.
- **Relance** : `valid/offres.jsonl` est réécrit à chaque collecte complète et jamais complété à la suite. Relancer ne crée donc pas de doublons.

## Bilan d'exécution

Exécuté le 24/11/2026 sur mon Mac (Docker Desktop, latence de l'API 0,12 s, Python 3.12). Les chiffres viennent des fichiers `logs/*_bilan.json`.

| Run | Scénario | Concurrence | Statut | Pages | Requêtes HTTP | Reprises | Offres vues | Valides | Rejetées | Durée |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| clean01 | clean | 3 | succès | 6/6 | 6 | 0 | 24 | 24 | 0 | 0,384 s |
| seq01 | clean | 1 (séquentiel) | succès | 6/6 | 6 | 0 | 24 | 24 | 0 | 0,773 s |
| atelier01 | atelier | 3 | succès | 6/6 | 9 | 3 | 24 | 20 | 4 | 1,763 s |
| panne01 | panne | 3 | **échec** | 5/6 | 8 | 2 | 20 | – | – | 2,163 s |

**Concurrent / séquentiel (clean)** : 0,384 s contre 0,773 s, soit environ 2 fois plus rapide. La page 1 est lue seule (il faut connaître `total_pages`), puis les 5 autres pages passent par groupes de 3 au lieu d'une par une. Le bilan montre au plus 3 appels simultanés en concurrent, et 1 en séquentiel : la limite est bien respectée.

**Atelier** : 9 requêtes HTTP pour 6 pages, car 3 pages ont eu besoin d'un 2e essai :
- page 2 : HTTP 429 → j'attends 1 s comme demandé par `Retry-After`, puis ça passe ;
- page 3 : HTTP 200 mais JSON cassé → nouvel essai après 0,5 s ;
- page 4 : timeout (plus de 1 s) → nouvel essai après 0,5 s.

Il ne faut pas confondre les 9 requêtes avec les 24 offres traitées. Les 4 rejets se trouvent dans `data/rejected/atelier_atelier01.jsonl` :

| Page | Position | Offre | Motif |
| --- | --- | --- | --- |
| 2 | 1 | O005 | champ manquant : supplier_id |
| 3 | 2 | O010 | price_cents n'est pas un entier : 'inconnu' |
| 5 | 1 | O017 | produit inconnu du catalogue : 9999 |
| 6 | 4 | O001 | doublon : O001 déjà reçu (page 1) |

24 vues = 20 valides + 4 rejetées, ce qui correspond au contrôle du livret. `data/valid/offres.jsonl` contient ces 20 offres : c'est l'entrée pour S4.

**Panne** : la page 6 renvoie HTTP 503 trois fois de suite (2 reprises, après 0,5 s puis 1 s), puis elle est abandonnée. La collecte est en échec (code de sortie 1) et rien n'est écrit dans `valid/`. Le fichier `offres.jsonl` du run atelier01 n'a donc pas été remplacé par un lot de 5 pages. Le raw et le log restent disponibles pour le diagnostic.
