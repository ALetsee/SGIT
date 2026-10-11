#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=/etc/sgit/sgit.env
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo: sudo ./reiniciar_datos.sh" >&2; exit 1; }
[[ -r "$ENV_FILE" ]] || { echo "No se encontro $ENV_FILE. ¿Esta instalado el SGIT?" >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a
: "${DB_NAME:?}" "${FOTOS_DIR:?}"
[[ "$FOTOS_DIR" != "/" && -d "$FOTOS_DIR" ]] || { echo "FOTOS_DIR invalido: $FOTOS_DIR" >&2; exit 1; }
cd /tmp
pg() { runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 -d "$DB_NAME" "$@"; }

N_OT="$(pg -tAc 'SELECT count(*) FROM orden_trabajo')"
N_CLI="$(pg -tAc 'SELECT count(*) FROM cliente')"
N_USR="$(pg -tAc "SELECT count(*) FROM usuario WHERE rol <> 'ADMIN'")"
N_FOTOS="$(find "$FOTOS_DIR" -type f | wc -l)"
echo "Se va a reiniciar la base '$DB_NAME':"
echo "  - $N_OT ordenes, $N_CLI clientes, $N_USR usuarios que no son administradores, $N_FOTOS fotografias"
echo "  - toda la bitacora de auditoria"
echo "  Se conservan estos administradores:"
pg -tAc "SELECT '      ' || email || CASE WHEN activo THEN '' ELSE '  (desactivado)' END FROM usuario WHERE rol='ADMIN' ORDER BY email"

if [[ "${1:-}" != "--si" ]]; then
  read -rp "Escribe BORRAR para continuar: " R
  [[ "$R" == "BORRAR" ]] || { echo "Cancelado: no se borro nada."; exit 1; }
fi

echo "Haciendo respaldo cifrado previo..."
if command -v sgit-respaldo >/dev/null; then
  sgit-respaldo || { echo "El respaldo fallo; no se borro nada." >&2; exit 1; }
else
  echo "AVISO: no se encontro sgit-respaldo; se continua sin respaldo." >&2
fi

pg <<'SQL'
BEGIN;
-- Todas las tablas de datos, menos usuario, configuracion y schema_version
SELECT format('TRUNCATE TABLE %s RESTART IDENTITY', string_agg(format('%I', tablename), ', '))
  FROM pg_tables
 WHERE schemaname = 'public' AND tablename NOT IN ('usuario', 'configuracion', 'schema_version') \gexec
DELETE FROM usuario WHERE rol <> 'ADMIN';
COMMIT;
SQL
find "$FOTOS_DIR" -mindepth 1 -delete

echo
echo "Listo. Datos reiniciados; los folios empiezan otra vez en 1."
echo "Ya puedes volver a correr: python3 cargar_demo.py"
