#!/usr/bin/env bash
# Rejoue la chaîne S1 et enregistre les sorties dans docs/resultats/ (preuves M2 à M5, A1).
# À lancer depuis novamarket/ :  bash s1/travail/capturer_resultats.sh
set -euo pipefail
OUT="s1/travail/docs/resultats"
mkdir -p "$OUT"
PSQL=(docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket)
"${PSQL[@]}" -f /s1/travail/sql/run_all.sql      > "$OUT/01_import_et_controles.txt" 2>&1
"${PSQL[@]}" -f /s1/travail/sql/indicateurs.sql  > "$OUT/02_indicateurs.txt" 2>&1
"${PSQL[@]}" -f /s1/travail/sql/anomalies.sql    > "$OUT/03_anomalies.txt" 2>&1
"${PSQL[@]}" -f /s1/travail/sql/A1_normalisation.sql > "$OUT/04_A1_normalisation.txt" 2>&1
"${PSQL[@]}" -f /s1/travail/sql/A1_jointures.sql > "$OUT/05_A1_jointures.txt" 2>&1
"${PSQL[@]}" -c "\\copy (SELECT source, ligne_fichier, cle, regle, cause, contenu FROM reception.rejets ORDER BY source, ligne_fichier) TO STDOUT WITH (FORMAT csv, HEADER true)" > "$OUT/rejets.csv"
echo "Résultats écrits dans $OUT"
