#!/usr/bin/env bash
# Respaldo cifrado del SGIT (RNF-07): base de datos, copia base de PostgreSQL y fotografias.
#   sudo sgit-respaldo
# El archivado continuo de WAL (en /var/backups/sgit_wal) junto con la copia base permite recuperar
# la base a un MOMENTO EXACTO (ver docs/LEEME.md, "Recuperacion ante desastre"). Se prueba con
#   sudo sgit-probar --respaldo
set -euo pipefail
ENV_FILE=/etc/sgit/sgit.env
KEY=/etc/sgit/respaldo.key
DESTINO=/var/backups/sgit
WAL_DIR=/var/backups/sgit_wal
RETENCION_DIAS="${SGIT_RETENCION_DIAS:-30}"

[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
[[ -r "$ENV_FILE" && -r "$KEY" ]] || { echo "Faltan $ENV_FILE o $KEY." >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a

umask 077
mkdir -p "$DESTINO"
cd /tmp
F="$(date +%Y%m%d_%H%M%S)"
CIFRAR=(openssl enc -aes-256-cbc -pbkdf2 -salt -pass "file:$KEY")
DESCIFRAR=(openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:$KEY")
PG() { runuser -u postgres -- "$@"; }

# 1) Volcado logico de la base (restauracion sencilla)
PG pg_dump --no-owner "$DB_NAME" | gzip -9 | "${CIFRAR[@]}" -out "$DESTINO/bd_$F.sql.gz.enc"
CABECERA="$( { "${DESCIFRAR[@]}" -in "$DESTINO/bd_$F.sql.gz.enc" | gunzip | head -n 5; } 2>/dev/null || true )"
[[ "$CABECERA" == *"PostgreSQL database dump"* ]] || { echo "ERROR: el respaldo de la base no se pudo verificar." >&2; exit 1; }

# 2) Fotografias
tar czf - -C "$(dirname "$FOTOS_DIR")" "$(basename "$FOTOS_DIR")" | "${CIFRAR[@]}" -out "$DESTINO/fotos_$F.tar.gz.enc"

# 3) Copia base de PostgreSQL (con el archivo de WAL permite recuperar a un momento exacto)
BASE_OK="no se hizo (el archivado de WAL no esta activo)"
if [[ "$(PG psql -X -qtAc 'SHOW archive_mode' 2>/dev/null)" == "on" && -d "$WAL_DIR" ]]; then
  PG pg_basebackup -D - -Ft -X fetch -c fast 2>/dev/null | gzip -9 | "${CIFRAR[@]}" -out "$DESTINO/base_$F.tar.gz.enc"
  # grep -c lee todo el flujo (con -q cerraria el pipe antes de tiempo y pipefail lo daria por fallido)
  N_ETIQUETA="$( { "${DESCIFRAR[@]}" -in "$DESTINO/base_$F.tar.gz.enc" | gunzip | tar -t; } 2>/dev/null | grep -c '^backup_label$' || true )"
  if [[ "$N_ETIQUETA" == "1" ]]; then
    BASE_OK="verificada"
  else
    echo "ERROR: la copia base de PostgreSQL no se pudo verificar." >&2; rm -f "$DESTINO/base_$F.tar.gz.enc"; exit 1
  fi
  PG psql -X -qc "SELECT pg_switch_wal()" >/dev/null 2>&1 || true   # fuerza el archivado del ultimo segmento
fi

# Retencion: se borra lo viejo (el WAL se conserva un dia mas que las copias base)
find "$DESTINO" -name '*.enc' -mtime +"$RETENCION_DIAS" -delete
[[ -d "$WAL_DIR" ]] && find "$WAL_DIR" -type f -mtime +"$((RETENCION_DIAS + 1))" -delete
echo "Respaldo verificado: $DESTINO/bd_$F.sql.gz.enc y fotos_$F.tar.gz.enc; copia base: $BASE_OK (retencion: $RETENCION_DIAS dias)."
