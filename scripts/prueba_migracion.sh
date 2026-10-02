#!/usr/bin/env bash
# Verifica que las migraciones dejen una base antigua IDENTICA a una instalacion nueva.
#   1) crea una base con el esquema historico (version 3)
#   2) le aplica las migraciones pendientes, en orden
#   3) crea otra base con schema.sql (instalacion nueva)
#   4) compara la estructura completa de ambas
# Usa bases temporales; no toca taller_db. Ejecutar como root.
set -uo pipefail
DIR="${SGIT_DB_DIR:-/opt/sgit/database}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
[[ -f "$DIR/schema.sql" && -f "$DIR/historial/schema_v3.sql" ]] || { echo "No se encontro $DIR/schema.sql o historial/schema_v3.sql" >&2; exit 1; }
cd /tmp
PG() { runuser -u postgres -- "$@"; }
FRESCA="sgit_mig_nueva_$$"; MIGRADA="sgit_mig_vieja_$$"
limpiar() { PG dropdb --if-exists "$FRESCA" >/dev/null 2>&1; PG dropdb --if-exists "$MIGRADA" >/dev/null 2>&1; }
trap limpiar EXIT
PG createdb "$FRESCA"; PG createdb "$MIGRADA"
FALLOS=0
PG psql -X -q -v ON_ERROR_STOP=1 -d "$FRESCA" -f "$DIR/schema.sql" >/tmp/mig_nueva.log 2>&1 && echo "OK    instalacion nueva (schema.sql)" || { echo "FALLO instalacion nueva: $(tail -3 /tmp/mig_nueva.log)"; FALLOS=1; }
PG psql -X -q -v ON_ERROR_STOP=1 -d "$MIGRADA" -f "$DIR/historial/schema_v3.sql" >/tmp/mig_vieja.log 2>&1 && echo "OK    esquema historico version 3" || { echo "FALLO esquema historico: $(tail -3 /tmp/mig_vieja.log)"; FALLOS=1; }
# datos en la base vieja: la migracion debe conservarlos
PG psql -X -q -d "$MIGRADA" -c "INSERT INTO cliente(nombre) VALUES ('dato previo a la migracion')" >/dev/null 2>&1
VER="$(PG psql -X -q -d "$MIGRADA" -tAc 'SELECT max(version) FROM schema_version')"
for f in $(ls "$DIR"/migraciones/*.sql 2>/dev/null | sort); do
  n=$((10#$(basename "$f" | cut -c1-3)))
  if (( n > VER )); then
    PG psql -X -q -v ON_ERROR_STOP=1 -d "$MIGRADA" -f "$f" >/tmp/mig_paso.log 2>&1 && echo "OK    migracion $(basename "$f")" || { echo "FALLO migracion $(basename "$f"): $(tail -3 /tmp/mig_paso.log)"; FALLOS=1; }
  fi
done
[[ "$(PG psql -X -q -d "$MIGRADA" -tAc "SELECT count(*) FROM cliente WHERE nombre='dato previo a la migracion'")" == "1" ]] && echo "OK    los datos existentes se conservaron" || { echo "FALLO se perdieron datos"; FALLOS=1; }
V1="$(PG psql -X -q -d "$FRESCA" -tAc 'SELECT max(version) FROM schema_version')"; V2="$(PG psql -X -q -d "$MIGRADA" -tAc 'SELECT max(version) FROM schema_version')"
[[ "$V1" == "$V2" ]] && echo "OK    misma version de esquema en ambas ($V1)" || { echo "FALLO versiones distintas: nueva=$V1 migrada=$V2"; FALLOS=1; }
norm() { PG pg_dump -s --no-owner "$1" | grep -vE '^\\(un)?restrict'; }
norm "$FRESCA" > /tmp/mig_a.sql; norm "$MIGRADA" > /tmp/mig_b.sql
if diff /tmp/mig_a.sql /tmp/mig_b.sql > /tmp/mig.diff; then echo "OK    estructura identica ($(wc -l < /tmp/mig_a.sql) lineas comparadas, 0 diferencias)"
else echo "FALLO la estructura difiere:"; head -20 /tmp/mig.diff; FALLOS=1; fi
echo; [[ $FALLOS -eq 0 ]] && echo "Resultado: migraciones correctas." || echo "Resultado: hay fallos en las migraciones."
exit $FALLOS
