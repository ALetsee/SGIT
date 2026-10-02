#!/usr/bin/env bash
# Pruebas del SGIT instalado.
#   sudo sgit-probar              reglas de negocio, seguridad y migraciones (seguro, no deja datos)
#   sudo sgit-probar --respaldo   ademas, recuperacion a un momento exacto (copia base cifrada + WAL)
#   sudo sgit-probar --completo   todo lo anterior y ademas API, pantallas y concurrencia
#                                 (crea registros con el prefijo PRUEBA)
set -uo pipefail
BASE=/opt/sgit
MODO="${1:-}"
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
case "$MODO" in ""|--respaldo|--completo) ;; *) echo "Opcion desconocida: $MODO (usa --respaldo o --completo)" >&2; exit 2;; esac
RES=0

echo "=== Reglas de negocio en la base de datos ==="
SGIT_ENV=/etc/sgit/sgit.env "$BASE/scripts/prueba_reglas_sql.sh" || RES=1

echo; echo "=== Seguridad (autoevaluacion de controles) ==="
SGIT_ENV=/etc/sgit/sgit.env "$BASE/scripts/prueba_seguridad.sh" || RES=1

echo; echo "=== Migraciones de la base de datos ==="
SGIT_DB_DIR="$BASE/database" "$BASE/scripts/prueba_migracion.sh" || RES=1

if [[ "$MODO" == "--respaldo" || "$MODO" == "--completo" ]]; then
  echo; echo "=== Recuperacion ante desastre (a un momento exacto) ==="
  SGIT_ENV=/etc/sgit/sgit.env "$BASE/scripts/prueba_respaldo_wal.sh" || RES=1
fi

if [[ "$MODO" == "--completo" ]]; then
  echo
  echo "AVISO: la prueba completa crea usuarios, clientes y ordenes con el prefijo PRUEBA."
  echo "La bitacora de auditoria es inmutable, asi que esos registros no se pueden borrar."
  echo "Usala antes de capturar datos reales (o reinstala con --reset-db despues)."
  EMAIL="${SGIT_ADMIN_EMAIL:-}"; PW="${SGIT_ADMIN_PASSWORD:-}"
  [[ -n "$EMAIL" ]] || read -rp "Correo del administrador: " EMAIL
  [[ -n "$PW" ]] || { read -rsp "Contrasena del administrador: " PW; echo; }
  set -a; . /etc/sgit/sgit.env; set +a
  echo; echo "=== API ==="
  SGIT_API="$SGIT_API" SGIT_ADMIN_EMAIL="$EMAIL" SGIT_ADMIN_PASSWORD="$PW" "$BASE/scripts/prueba_api.sh" || RES=1
  echo; echo "=== Pantallas (frontend) ==="
  SGIT_FRONTEND_DIR="$BASE/frontend" SGIT_API="$SGIT_API" SGIT_ADMIN_EMAIL="$EMAIL" SGIT_ADMIN_PASSWORD="$PW" \
    python3 "$BASE/scripts/prueba_frontend.py" || RES=1
  echo; echo "=== Concurrencia (varios tecnicos a la vez) ==="
  SGIT_API="$SGIT_API" SGIT_ADMIN_EMAIL="$EMAIL" SGIT_ADMIN_PASSWORD="$PW" \
    python3 "$BASE/scripts/prueba_concurrencia.py" || RES=1
  # Los usuarios de prueba tienen una contrasena conocida: se desactivan siempre al terminar.
  N="$(runuser -u postgres -- psql -X -q -d "${DB_NAME:-taller_db}" -tAc "WITH x AS (UPDATE usuario SET activo=false WHERE email LIKE '%@prueba.test' AND activo RETURNING 1) SELECT count(*) FROM x")"
  echo; echo "Usuarios de prueba desactivados: ${N:-0} (sus registros quedan en la bitacora, que es inmutable)."
fi
echo
[[ $RES -eq 0 ]] && echo "TODAS LAS PRUEBAS SOLICITADAS PASARON." || echo "HAY PRUEBAS CON FALLO: revisa la salida anterior."
exit $RES
