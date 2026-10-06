#!/usr/bin/env bash
# Verifica que las migraciones dejen una base antigua IDENTICA a una instalacion nueva, desde CADA version historica.
#   para cada esquema de database/historial/: crea una base con ese esquema (y un dato), le aplica las
#   migraciones pendientes en orden y compara su estructura completa con la de una instalacion nueva.
# Usa bases temporales; no toca taller_db. Ejecutar como root.
set -uo pipefail
DIR="${SGIT_DB_DIR:-/opt/sgit/database}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
[[ -f "$DIR/schema.sql" ]] || { echo "No se encontro $DIR/schema.sql" >&2; exit 1; }
cd /tmp
PG() { runuser -u postgres -- "$@"; }
FRESCA="sgit_mig_nueva_$$"; TMPS=()
limpiar() { PG dropdb --if-exists "$FRESCA" >/dev/null 2>&1; for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && PG dropdb --if-exists "$d" >/dev/null 2>&1; done; }
trap limpiar EXIT
FALLOS=0
norm() { PG pg_dump -s --no-owner "$1" | grep -vE '^\\(un)?restrict'; }
PG createdb "$FRESCA"
PG psql -X -q -v ON_ERROR_STOP=1 -d "$FRESCA" -f "$DIR/schema.sql" >/tmp/mig_nueva.log 2>&1 && echo "OK    instalacion nueva (schema.sql)" || { echo "FALLO instalacion nueva: $(tail -3 /tmp/mig_nueva.log)"; FALLOS=1; }
V_NUEVA="$(PG psql -X -q -d "$FRESCA" -tAc 'SELECT max(version) FROM schema_version')"
norm "$FRESCA" > /tmp/mig_a.sql

for H in $(ls "$DIR"/historial/schema_v*.sql 2>/dev/null | sort -V); do
  V0="$(basename "$H" .sql | sed 's/schema_v//')"
  D="sgit_mig_v${V0}_$$"; TMPS+=("$D"); PG createdb "$D"
  if ! PG psql -X -q -v ON_ERROR_STOP=1 -d "$D" -f "$H" >/tmp/mig_vieja.log 2>&1; then echo "FALLO esquema historico v$V0: $(tail -3 /tmp/mig_vieja.log)"; FALLOS=1; continue; fi
  PG psql -X -q -d "$D" -c "INSERT INTO cliente(nombre) VALUES ('dato previo a la migracion')" >/dev/null 2>&1
  VER="$(PG psql -X -q -d "$D" -tAc 'SELECT max(version) FROM schema_version')"
  for f in $(ls "$DIR"/migraciones/*.sql 2>/dev/null | sort); do
    n=$((10#$(basename "$f" | cut -c1-3)))
    if (( n > VER )); then
      PG psql -X -q -v ON_ERROR_STOP=1 -d "$D" < "$f" >/tmp/mig_paso.log 2>&1 && echo "OK    desde v$V0: migracion $(basename "$f")" || { echo "FALLO desde v$V0: migracion $(basename "$f"): $(tail -3 /tmp/mig_paso.log)"; FALLOS=1; }
    fi
  done
  [[ "$(PG psql -X -q -d "$D" -tAc "SELECT count(*) FROM cliente WHERE nombre='dato previo a la migracion'")" == "1" ]] && echo "OK    desde v$V0: los datos existentes se conservaron" || { echo "FALLO desde v$V0: se perdieron datos"; FALLOS=1; }
  V2="$(PG psql -X -q -d "$D" -tAc 'SELECT max(version) FROM schema_version')"
  [[ "$V_NUEVA" == "$V2" ]] && echo "OK    desde v$V0: misma version de esquema que la instalacion nueva ($V_NUEVA)" || { echo "FALLO desde v$V0: versiones distintas: nueva=$V_NUEVA migrada=$V2"; FALLOS=1; }
  norm "$D" > /tmp/mig_b.sql
  if diff /tmp/mig_a.sql /tmp/mig_b.sql > /tmp/mig.diff; then echo "OK    desde v$V0: estructura identica ($(wc -l < /tmp/mig_a.sql) lineas comparadas, 0 diferencias)"
  else echo "FALLO desde v$V0: la estructura difiere:"; head -20 /tmp/mig.diff; FALLOS=1; fi
done
echo; [[ $FALLOS -eq 0 ]] && echo "Resultado: migraciones correctas." || echo "Resultado: hay fallos en las migraciones."
exit $FALLOS
