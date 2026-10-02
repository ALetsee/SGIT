#!/usr/bin/env bash
# Prueba de recuperacion ante desastre (RNF-07): restaura la base A UN MOMENTO EXACTO usando la copia
# base cifrada y el archivo de WAL, en un clúster temporal aparte (no toca la base real).
#   1) crea una base temporal con datos "antes"        2) hace el respaldo (copia base cifrada)
#   3) agrega un dato, marca la hora T, agrega "despues"   4) restaura la copia base + WAL hasta T
#   5) comprueba que estan los datos hasta T y que NO esta lo posterior
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
ENV_FILE="${SGIT_ENV:-/etc/sgit/sgit.env}"; set -a; . "$ENV_FILE"; set +a
WAL_DIR=/var/backups/sgit_wal; KEY=/etc/sgit/respaldo.key; DESTINO=/var/backups/sgit
RESPALDO="${SGIT_RESPALDO_CMD:-/usr/local/bin/sgit-respaldo}"
cd /tmp
PG() { runuser -u postgres -- "$@"; }
Q()  { PG psql -X -qtA "$@"; }
T0="$(date +%s)"; DB="sgit_pitr_$$"; RD="/tmp/sgit_pitr_$$"; PUERTO=5499; FALLOS=0
ok()  { echo "OK    $1"; }
mal() { echo "FALLO $1"; FALLOS=1; }
limpiar() { [[ -d "$RD" ]] && PG "$BIN/pg_ctl" -D "$RD" -m immediate stop >/dev/null 2>&1; rm -rf "$RD"; Q -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1; }
trap limpiar EXIT

[[ "$(Q -c 'SHOW archive_mode')" == "on" && -d "$WAL_DIR" ]] && ok "el archivado de WAL esta activo" || { mal "el archivado de WAL NO esta activo (ejecuta el instalador)"; exit 1; }
MAYOR="$(Q -c 'SHOW server_version_num' | cut -c1-2)"; BIN="/usr/lib/postgresql/$MAYOR/bin"
[[ -x "$BIN/pg_ctl" ]] || { mal "no se encontro pg_ctl en $BIN"; exit 1; }

Q -c "CREATE DATABASE $DB" >/dev/null
Q -d "$DB" -c "CREATE TABLE t(v text, creado timestamptz DEFAULT clock_timestamp()); INSERT INTO t(v) VALUES ('antes-1'),('antes-2')" >/dev/null
"$RESPALDO" > /tmp/sgit_pitr_respaldo.log 2>&1 && ok "respaldo hecho: $(tail -1 /tmp/sgit_pitr_respaldo.log | sed 's/.*copia base: //')" || { mal "el respaldo fallo: $(tail -2 /tmp/sgit_pitr_respaldo.log)"; exit 1; }
BASE="$(ls -t "$DESTINO"/base_*.tar.gz.enc 2>/dev/null | head -1)"; [[ -n "$BASE" ]] && ok "copia base cifrada: $(basename "$BASE")" || { mal "no hay copia base"; exit 1; }

sleep 1
Q -d "$DB" -c "INSERT INTO t(v) VALUES ('antes-3')" >/dev/null
sleep 2; PUNTO="$(Q -c 'SELECT now()')"; sleep 2
Q -d "$DB" -c "INSERT INTO t(v) VALUES ('despues-1')" >/dev/null
SEG="$(Q -c 'SELECT pg_walfile_name(pg_switch_wal())')"
for i in $(seq 1 60); do [[ -f "$WAL_DIR/$SEG" ]] && break; sleep 1; done
[[ -f "$WAL_DIR/$SEG" ]] && ok "el WAL posterior al punto ya esta archivado ($SEG)" || { mal "el WAL no se archivo a tiempo"; exit 1; }
echo "      punto de recuperacion elegido: $PUNTO"

mkdir -p "$RD"
openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:$KEY" -in "$BASE" | gunzip | tar -x -C "$RD" && ok "copia base descifrada y extraida" || { mal "no se pudo extraer la copia base"; exit 1; }
chown -R postgres:postgres "$RD"; chmod 700 "$RD"
# Configuracion propia del clúster temporal: NO hereda el archivado ni los puertos del clúster real
: > "$RD/postgresql.conf"; echo "local all all trust" > "$RD/pg_hba.conf"; : > "$RD/pg_ident.conf"
cat > "$RD/postgresql.auto.conf" <<CONF
restore_command = 'cp $WAL_DIR/%f %p'
recovery_target_time = '$PUNTO'
recovery_target_action = 'promote'
archive_mode = off
CONF
touch "$RD/recovery.signal"; chown -R postgres:postgres "$RD"
if PG "$BIN/pg_ctl" -D "$RD" -o "-p $PUERTO -c listen_addresses='' -c unix_socket_directories=$RD" -w -t 180 -l "$RD/log.txt" start >/dev/null 2>&1; then ok "el clúster restaurado arranca y llega al punto elegido"
else mal "el clúster restaurado no arranco: $(tail -5 "$RD/log.txt" 2>/dev/null)"; exit 1; fi
for i in $(seq 1 30); do [[ "$(PG psql -X -qtA -h "$RD" -p $PUERTO -d postgres -c 'SELECT pg_is_in_recovery()' 2>/dev/null)" == "f" ]] && break; sleep 1; done
R="$(PG psql -X -qtA -h "$RD" -p $PUERTO -d "$DB" -c "SELECT string_agg(v, ',' ORDER BY v) FROM t" 2>/dev/null)"
[[ "$R" == "antes-1,antes-2,antes-3" ]] && ok "RECUPERADO A UN MOMENTO EXACTO: estan los 3 datos anteriores al punto ($R)" || mal "datos recuperados inesperados: '$R' (se esperaba antes-1,antes-2,antes-3)"
[[ "$R" != *despues* ]] && ok "lo posterior al punto NO esta (despues-1 quedó fuera)" || mal "aparecio un dato posterior al punto"
N="$(PG psql -X -qtA -h "$RD" -p $PUERTO -d postgres -c "SELECT count(*) FROM pg_database WHERE datname='${DB_NAME:-taller_db}'" 2>/dev/null)"
[[ "$N" == "1" ]] && ok "la base real del taller (${DB_NAME:-taller_db}) también viene en la copia" || mal "la base del taller no está en la copia"
echo "      duración de la prueba: $(( $(date +%s) - T0 )) segundos"
echo; [[ $FALLOS -eq 0 ]] && echo "Resultado: la recuperación a un punto exacto funciona." || echo "Resultado: hay fallos en la recuperación."
exit $FALLOS
