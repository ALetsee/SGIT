#!/usr/bin/env bash

set -euo pipefail
umask 022
SELF="$(readlink -f "$0")"

DEST=/opt/sgit
CONF_DIR=/etc/sgit
ENV_FILE="$CONF_DIR/sgit.env"
TLS_DIR="$CONF_DIR/tls"
DATA_DIR=/var/lib/sgit
BACKUP_DIR=/var/backups/sgit
LOG=/var/log/sgit_instalacion.log
DB_NAME=taller_db
DB_USER=app_taller
RESET_DB=0
SIN_NGINX=0
FOTOS_MIN=""
ADMIN_EMAIL="admin@electromotorservices.local"
DOMINIO=""
CORREO=""
LETSENCRYPT=0
SIN_WAL=0

C_OK="\033[1;32m"; C_WARN="\033[1;33m"; C_ERR="\033[1;31m"; C_INFO="\033[1;36m"; C_RESET="\033[0m"
paso() { echo -e "\n${C_INFO}== $* ==${C_RESET}"; }
log()  { echo -e "${C_INFO}[INFO]${C_RESET} $*"; }
ok()   { echo -e "${C_OK}[ OK ]${C_RESET} $*"; }
warn() { echo -e "${C_WARN}[AVISO]${C_RESET} $*"; }
fail() { echo -e "${C_ERR}[FALLO]${C_RESET} $*" >&2; exit 1; }

uso() { awk '/^####/ { n++; if (n == 2) exit; next } n == 1 { print }' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset-db) RESET_DB=1 ;;
    --sin-nginx) SIN_NGINX=1 ;;
    --fotos-minimas) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || fail "--fotos-minimas requiere un numero."; FOTOS_MIN="$2"; shift ;;
    --admin-correo) [[ $# -ge 2 ]] || fail "--admin-correo requiere un valor."; ADMIN_EMAIL="$2"; shift ;;
    --dominio) [[ $# -ge 2 ]] || fail "--dominio requiere un valor."; DOMINIO="$2"; shift ;;
    --letsencrypt) LETSENCRYPT=1 ;;
    --correo) [[ $# -ge 2 ]] || fail "--correo requiere un valor."; CORREO="$2"; shift ;;
    --sin-wal) SIN_WAL=1 ;;
    -h|--ayuda) uso; exit 0 ;;
    *) fail "Opcion desconocida: $1 (usa --ayuda)" ;;
  esac
  shift
done

[[ $EUID -eq 0 ]] || fail "Ejecuta con sudo: sudo ./sgit-instalador.sh"
command -v apt-get >/dev/null || fail "Este instalador es para Ubuntu o Debian."

mkdir -p "$(dirname "$LOG")"; touch "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
trap 'fail "Error inesperado en la linea $LINENO. Revisa $LOG. Puedes volver a ejecutar el instalador (es idempotente)."' ERR
echo "=== Instalacion SGIT - $(date -Is) ==="

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd /tmp

paso "0/9 Desempaquetando el proyecto"
LINEA="$(awk '/^__SGIT_PAYLOAD_BELOW__$/ {print NR + 1; exit}' "$SELF")"
[[ -n "$LINEA" ]] || fail "El instalador esta incompleto (no contiene el proyecto)."
tail -n +"$LINEA" "$SELF" | tar xz -C "$TMP" || fail "No se pudo extraer el proyecto: el archivo esta danado. Descargalo de nuevo."
for d in backend-go frontend-py database scripts; do [[ -d "$TMP/$d" ]] || fail "Falta la carpeta $d en el paquete."; done
ok "Proyecto extraido"

paso "1/9 Paquetes del sistema"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || fail "No se pudo ejecutar apt-get update. Revisa la conexion a Internet."
BASE=(postgresql golang-go python3 python3-flask python3-requests python3-cryptography gunicorn openssl curl ca-certificates cron iproute2 logrotate)
[[ $SIN_NGINX -eq 1 ]] || BASE+=(nginx)
apt-get install -y -qq "${BASE[@]}" || fail "No se pudieron instalar los paquetes base."
USAR_MODULOS=0
if apt-get install -y -qq golang-github-lib-pq-dev golang-golang-x-crypto-dev golang-golang-x-sys-dev; then
  ok "Librerias de Go instaladas desde el sistema (compilacion sin descargas externas)"
else
  warn "No se encontraron las librerias de Go en apt; se descargaran con 'go mod' (requiere Internet)."
  USAR_MODULOS=1
fi
GOV="$(go version | awk '{print $3}' | sed 's/^go//')"
GMAJ="${GOV%%.*}"; GREST="${GOV#*.}"; GMIN="${GREST%%.*}"
(( GMAJ > 1 || (GMAJ == 1 && GMIN >= 22) )) || fail "Se requiere Go 1.22 o superior y hay $GOV. En Ubuntu 24.04 o mas nuevo viene por defecto."
ok "Go $GOV, Python $(python3 -V | awk '{print $2}')"

paso "2/9 Usuario de servicio y carpetas"
id sgit >/dev/null 2>&1 || useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin sgit
install -d -m 755 "$DEST" "$DEST/bin"
install -d -m 750 -o sgit -g sgit "$DATA_DIR" "$DATA_DIR/fotos"
install -d -m 750 "$BACKUP_DIR" "$CONF_DIR"
ok "Usuario 'sgit' y carpetas listas"

paso "3/9 PostgreSQL"
SYSTEMD=0; [[ -d /run/systemd/system ]] && SYSTEMD=1
pgsu() { runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 "$@"; }
if ! pg_isready -q 2>/dev/null; then
  if [[ $SYSTEMD -eq 1 ]]; then systemctl enable --now postgresql >/dev/null 2>&1 || true; fi
  if ! pg_isready -q 2>/dev/null && command -v pg_lsclusters >/dev/null; then
    while read -r ver nom _; do pg_ctlcluster "$ver" "$nom" start 2>/dev/null || true; done < <(pg_lsclusters -h)
  fi
  for _ in $(seq 1 30); do pg_isready -q 2>/dev/null && break; sleep 1; done
fi
pg_isready -q || fail "PostgreSQL no esta en linea. Revisa 'pg_lsclusters' y los registros de PostgreSQL."
PG_PORT="$(pgsu -tAc 'SHOW port')"
PG_VER="$(pgsu -tAc 'SHOW server_version' | awk '{print $1}')"
ok "PostgreSQL $PG_VER en el puerto $PG_PORT"
if ss -ltnH "sport = :$PG_PORT" 2>/dev/null | awk '{print $4}' | grep -qE '^(0\.0\.0\.0|\*|\[::\]):'; then
  warn "PostgreSQL escucha en todas las interfaces. El ERS pide solo localhost: ajusta listen_addresses."
fi

set_env() {
  if grep -q "^$1=" "$ENV_FILE"; then sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"; else echo "$1=$2" >> "$ENV_FILE"; fi
}
if [[ ! -f "$ENV_FILE" ]]; then
  umask 077
  cat > "$ENV_FILE" <<EOF
# Generado por el instalador del SGIT. Contiene secretos: no compartir ni subir a git.
DB_HOST=127.0.0.1
DB_PORT=$PG_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)
JWT_SECRET=$(openssl rand -hex 32)
JWT_EXPIRES_HOURS=8
LISTEN_ADDR=127.0.0.1:8081
FOTOS_DIR=$DATA_DIR/fotos
FOTOS_MINIMAS=4
SGIT_API=http://127.0.0.1:8081
FLASK_SECRET=$(openssl rand -hex 32)
SGIT_COOKIE_SECURE=1
WEB_BIND=127.0.0.1:8000
SGIT_TZ=America/Mexico_City
EOF
  umask 022
  ok "Configuracion y secretos generados en $ENV_FILE"
else
  ok "Se conserva la configuracion existente ($ENV_FILE)"
fi
set_env DB_PORT "$PG_PORT"
if [[ -n "$DOMINIO" && -f "/etc/letsencrypt/live/$DOMINIO/fullchain.pem" ]]; then set_env SGIT_HSTS 1; else set_env SGIT_HSTS 0; fi
[[ -z "$FOTOS_MIN" ]] || set_env FOTOS_MINIMAS "$FOTOS_MIN"
if [[ $SIN_NGINX -eq 1 ]]; then set_env WEB_BIND 0.0.0.0:8000; set_env SGIT_COOKIE_SECURE 0
else set_env WEB_BIND 127.0.0.1:8000; set_env SGIT_COOKIE_SECURE 1; fi

ZONA="$(grep -E '^SGIT_TZ=' "$ENV_FILE" | head -1 | cut -d= -f2)"; ZONA="${ZONA:-America/Mexico_City}"
[[ -e "/usr/share/zoneinfo/$ZONA" ]] || fail "La zona horaria '$ZONA' (SGIT_TZ en $ENV_FILE) no existe en este sistema."
set_env SGIT_TZ "$ZONA"; set_env TZ "$ZONA"
chown root:sgit "$ENV_FILE"; chmod 640 "$ENV_FILE"
set -a; . "$ENV_FILE"; set +a

ENV_FILE_WEB="$CONF_DIR/sgit-web.env"
grep -E '^(SGIT_API|SGIT_TZ|FLASK_SECRET|SGIT_COOKIE_SECURE|SGIT_HSTS|TZ)=' "$ENV_FILE" > "$ENV_FILE_WEB"
chown root:sgit "$ENV_FILE_WEB"; chmod 640 "$ENV_FILE_WEB"

pgsu -v pw="$DB_PASSWORD" -v rol="$DB_USER" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE', :'rol')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'rol') \gexec
SELECT format('ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'rol', :'pw') \gexec
SQL
ok "Rol '$DB_USER' sincronizado (sin superusuario)"

ULTIMA=3
for f in "$TMP"/database/migraciones/*.sql; do
  [[ -e "$f" ]] || continue
  n=$((10#$(basename "$f" | cut -c1-3))); (( n > ULTIMA )) && ULTIMA=$n
done
EXISTE="$(pgsu -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")"
if [[ "$EXISTE" == "1" ]]; then
  VER="$(pgsu -d "$DB_NAME" -tAc "SELECT max(version) FROM schema_version" 2>/dev/null || true)"
  if [[ $RESET_DB -eq 1 ]]; then
    PREVIO="$BACKUP_DIR/previa_${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql.gz"
    log "Respaldando la base actual en $PREVIO antes de recrearla..."
    ( umask 077; runuser -u postgres -- pg_dump "$DB_NAME" | gzip > "$PREVIO" )
    pgsu -c "DROP DATABASE $DB_NAME WITH (FORCE)"
    EXISTE=""
    ok "Base anterior eliminada (respaldo guardado)"
  elif [[ "$VER" =~ ^[0-9]+$ ]] && (( VER == ULTIMA )); then
    ok "La base '$DB_NAME' ya tiene el esquema version $ULTIMA; se conserva con sus datos"
  elif [[ "$VER" =~ ^[0-9]+$ ]] && (( VER >= 3 && VER < ULTIMA )); then
    PREVIO="$BACKUP_DIR/previa_migracion_v${VER}_$(date +%Y%m%d_%H%M%S).sql.gz"
    log "La base tiene el esquema version $VER; se actualiza a la $ULTIMA (respaldo previo en $PREVIO)..."
    ( umask 077; runuser -u postgres -- pg_dump "$DB_NAME" | gzip > "$PREVIO" )
    for f in $(ls "$TMP"/database/migraciones/*.sql | sort); do
      n=$((10#$(basename "$f" | cut -c1-3)))
      if (( n > VER )); then

        if ! pgsu -d "$DB_NAME" < "$f"; then fail "Fallo la migracion $(basename "$f"). Cada migracion es una transaccion, asi que la base quedo como estaba. Respaldo en $PREVIO."; fi
        ok "Migracion $(basename "$f") aplicada; tus datos se conservaron"
      fi
    done
  else
    fail "La base '$DB_NAME' ya existe con un esquema que no reconozco (version '${VER:-sin version}'). Para empezar de cero ejecuta de nuevo con --reset-db (hace un respaldo antes)."
  fi
fi
if [[ "$EXISTE" != "1" ]]; then
  pgsu -c "CREATE DATABASE $DB_NAME"
  pgsu -d "$DB_NAME" -c "REVOKE ALL ON DATABASE $DB_NAME FROM PUBLIC; GRANT CONNECT ON DATABASE $DB_NAME TO $DB_USER; REVOKE CREATE ON SCHEMA public FROM PUBLIC;"
  pgsu -d "$DB_NAME" < "$TMP/database/schema.sql"
  ok "Esquema aplicado: tablas, reglas RN-01 a RN-06, RLS y privilegios minimos"
fi
pgsu -c "ALTER DATABASE $DB_NAME SET timezone TO '$ZONA'" && ok "La base usa la hora del taller ($ZONA)"
VER_FINAL="$(pgsu -d "$DB_NAME" -tAc "SELECT max(version) FROM schema_version")"
[[ "$VER_FINAL" == "$ULTIMA" ]] || fail "El esquema quedo en la version $VER_FINAL y se esperaba la $ULTIMA."
TABLAS="$(pgsu -d "$DB_NAME" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")"
TRIG="$(pgsu -d "$DB_NAME" -tAc "SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal")"
ok "Esquema version $VER_FINAL: $TABLAS tablas/vistas y $TRIG triggers"

WAL_DIR=/var/backups/sgit_wal
reiniciar_pg() {
  if [[ $SYSTEMD -eq 1 ]]; then systemctl restart postgresql
  else while read -r ver nom _; do pg_ctlcluster "$ver" "$nom" restart; done < <(pg_lsclusters -h); fi
  for _ in $(seq 1 40); do pg_isready -q 2>/dev/null && return 0; sleep 1; done
  return 1
}
if [[ $SIN_WAL -eq 0 ]]; then
  install -d -m 700 -o postgres -g postgres "$WAL_DIR"
  CMD_WAL="test ! -f $WAL_DIR/%f && cp %p $WAL_DIR/%f"
  if [[ "$(pgsu -tAc 'SHOW archive_mode')" != "on" || "$(pgsu -tAc 'SHOW archive_command')" != "$CMD_WAL" ]]; then
    pgsu -c "ALTER SYSTEM SET archive_mode = 'on'"
    pgsu -c "ALTER SYSTEM SET archive_command = '$CMD_WAL'"
    pgsu -c "ALTER SYSTEM SET archive_timeout = '300'"
    log "Reiniciando PostgreSQL unos segundos para activar el archivado de WAL..."
    reiniciar_pg || fail "PostgreSQL no volvio a arrancar tras activar el archivado de WAL. Revisa los registros de PostgreSQL."
    ok "Archivado continuo de WAL activado (se pierde como maximo 5 minutos de datos ante un desastre)"
  else
    ok "El archivado continuo de WAL ya estaba activo"
  fi
else
  warn "Se omitio el archivado de WAL (--sin-wal): habra respaldo diario pero no recuperacion a un momento exacto."
fi

paso "4/9 Instalando el codigo"
rm -rf "$DEST/src" "$DEST/frontend" "$DEST/scripts" "$DEST/docs" "$DEST/database"
install -d "$DEST/src"
cp -a "$TMP/backend-go" "$DEST/src/backend-go"
cp -a "$TMP/frontend-py" "$DEST/frontend"
cp -a "$TMP/scripts" "$DEST/scripts"
cp -a "$TMP/database" "$DEST/database"
[[ -d "$TMP/docs" ]] && cp -a "$TMP/docs" "$DEST/docs"
find "$DEST/frontend" -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
chown -R root:root "$DEST"; chmod -R a+rX,go-w "$DEST"; chmod +x "$DEST"/scripts/*.sh "$DEST"/scripts/*.py
ok "Codigo en $DEST"

paso "5/9 Compilando la API en Go"
export GOCACHE="$TMP/gocache" GOFLAGS=""
compilar_gopath() { ( cd "$DEST/src/backend-go" && GO111MODULE=off GOPATH=/usr/share/gocode go build -o "$DEST/bin/sgit-api" . ); }
compilar_modulos() { ( cd "$DEST/src/backend-go" && GO111MODULE=on GOFLAGS=-mod=mod go mod tidy && GO111MODULE=on GOFLAGS=-mod=mod go build -o "$DEST/bin/sgit-api" . ); }
if [[ $USAR_MODULOS -eq 0 ]] && compilar_gopath; then ok "API compilada con las librerias del sistema"
elif compilar_modulos; then ok "API compilada con modulos de Go"
else fail "No se pudo compilar la API en Go. Revisa los mensajes anteriores."; fi
chmod 755 "$DEST/bin/sgit-api"

paso "6/9 Servicios"
mapfile -t ENVV < <(grep -E '^[A-Z_]+=' "$ENV_FILE")
GUNICORN="$(command -v gunicorn)"
if [[ $SYSTEMD -eq 1 ]]; then
  cat > /etc/systemd/system/sgit-api.service <<EOF
[Unit]
Description=SGIT API (Go)
StartLimitIntervalSec=0
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=sgit
Group=sgit
EnvironmentFile=$ENV_FILE
ExecStart=$DEST/bin/sgit-api
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_DIR
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/sgit-web.service <<EOF
[Unit]
Description=SGIT Frontend web (Python)
StartLimitIntervalSec=0
After=network.target sgit-api.service
Wants=sgit-api.service

[Service]
User=sgit
Group=sgit
EnvironmentFile=$ENV_FILE_WEB
WorkingDirectory=$DEST/frontend
ExecStart=$GUNICORN --workers 2 --threads 2 --bind \${WEB_BIND} --access-logfile - app:app
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable sgit-api sgit-web >/dev/null 2>&1
  systemctl restart sgit-api sgit-web
  ok "Servicios sgit-api y sgit-web habilitados (arrancan solos al reiniciar)"
else
  warn "No se detecto systemd (WSL o contenedor): inicio la API y la web en segundo plano."
  warn "Esto no sobrevive a un reinicio; en un servidor normal se usan los servicios systemd."
  pkill -x sgit-api 2>/dev/null || true; pkill -x gunicorn 2>/dev/null || true; sleep 1
  touch /var/log/sgit-api.log /var/log/sgit-web.log; chown sgit:sgit /var/log/sgit-api.log /var/log/sgit-web.log
  mapfile -t ENVV_WEB < <(grep -E '^(SGIT_API|SGIT_TZ|FLASK_SECRET|SGIT_COOKIE_SECURE|SGIT_HSTS|TZ)=' "$ENV_FILE")
  setsid runuser -u sgit -- env "${ENVV[@]}" "$DEST/bin/sgit-api" >>/var/log/sgit-api.log 2>&1 < /dev/null &

  setsid runuser -u sgit -- env -i PATH="$PATH" HOME=/home/sgit "${ENVV_WEB[@]}" "$GUNICORN" --workers 2 --threads 2 --bind "$WEB_BIND" --chdir "$DEST/frontend" app:app >>/var/log/sgit-web.log 2>&1 < /dev/null &
fi
esperar() { for _ in $(seq 1 40); do curl -fsS "$1" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
esperar "http://127.0.0.1:8081/salud" || fail "La API no respondio. Revisa: journalctl -u sgit-api -n 50 (o /var/log/sgit-api.log)"
esperar "http://${WEB_BIND/0.0.0.0/127.0.0.1}/salud" || fail "El frontend no respondio. Revisa: journalctl -u sgit-web -n 50 (o /var/log/sgit-web.log)"
ok "API (puerto 8081, solo local) y frontend (puerto 8000) responden"

paso "7/9 Primer administrador"
HAY_ADMIN="$(pgsu -d "$DB_NAME" -tAc "SELECT count(*) FROM usuario WHERE rol='ADMIN'")"
CRED_FILE=/root/sgit_admin_inicial.txt
ADMIN_PW=""
if [[ "$HAY_ADMIN" == "0" ]]; then
  ADMIN_PW="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 16)"
  runuser -u sgit -- env "${ENVV[@]}" SGIT_ADMIN_PASSWORD="$ADMIN_PW" "$DEST/bin/sgit-api" crear-admin "$ADMIN_EMAIL" "Administrador" >/dev/null
  ( umask 077; printf 'Correo: %s\nContrasena inicial: %s\n(Cambiala creando un usuario nuevo y desactivando este, o reinstalando con --reset-db)\n' "$ADMIN_EMAIL" "$ADMIN_PW" > "$CRED_FILE" )
  ok "Administrador creado: $ADMIN_EMAIL"
else
  ok "Ya existe un administrador; no se crea otro"
fi

paso "8/9 Nginx con TLS"
IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
URL="http://${WEB_BIND/0.0.0.0/${IP:-127.0.0.1}}"
if [[ $SIN_NGINX -eq 0 ]]; then
  CN="${DOMINIO:-${IP:-localhost}}"
  install -d -m 755 "$TLS_DIR"
  if [[ ! -f "$TLS_DIR/sgit.crt" ]]; then
    SAN="DNS:localhost"; [[ -n "$IP" ]] && SAN="$SAN,IP:$IP"; [[ -n "$DOMINIO" ]] && SAN="$SAN,DNS:$DOMINIO"
    openssl req -x509 -newkey rsa:2048 -nodes -days 825 -keyout "$TLS_DIR/sgit.key" -out "$TLS_DIR/sgit.crt" \
      -subj "/CN=$CN/O=Electro-Motor Services" -addext "subjectAltName=$SAN" >/dev/null 2>&1
    chmod 600 "$TLS_DIR/sgit.key"
    ok "Certificado TLS autofirmado creado (el navegador mostrara un aviso la primera vez)"
  else
    ok "Se conserva el certificado TLS existente en $TLS_DIR"
  fi
  CERT="$TLS_DIR/sgit.crt"; CLAVE="$TLS_DIR/sgit.key"
  if [[ -n "$DOMINIO" && -f "/etc/letsencrypt/live/$DOMINIO/fullchain.pem" ]]; then
    CERT="/etc/letsencrypt/live/$DOMINIO/fullchain.pem"; CLAVE="/etc/letsencrypt/live/$DOMINIO/privkey.pem"
  fi
  escribir_nginx() {
    cat > /etc/nginx/sites-available/sgit <<EOF
server {
    listen 80 default_server;
    server_name ${DOMINIO:-_};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl default_server;
    server_name ${DOMINIO:-_};
    ssl_certificate $CERT;
    ssl_certificate_key $CLAVE;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
    client_max_body_size 12m;
    server_tokens off;
    gzip on;
    gzip_vary on;
    gzip_min_length 512;
    gzip_types text/css application/javascript application/json image/svg+xml application/manifest+json;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }
}
EOF
  }
  escribir_nginx
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/sgit /etc/nginx/sites-enabled/sgit
  nginx -t || fail "La configuracion de Nginx no es valida."
  if [[ $SYSTEMD -eq 1 ]]; then systemctl enable nginx >/dev/null 2>&1; systemctl restart nginx
  else service nginx restart >/dev/null 2>&1 || nginx -s reload 2>/dev/null || nginx; fi
  URL="https://${DOMINIO:-${IP:-localhost}}"
  ok "Nginx sirve la web por HTTPS (con compresion) y redirige el puerto 80"
  if [[ $LETSENCRYPT -eq 1 && "$CERT" == "$TLS_DIR/sgit.crt" ]]; then
    [[ -n "$DOMINIO" && -n "$CORREO" ]] || fail "--letsencrypt requiere --dominio y --correo."
    log "Pidiendo el certificado de Let's Encrypt para $DOMINIO (el dominio debe apuntar a este servidor)..."
    install -d /var/www/html
    if apt-get install -y -qq certbot >/dev/null 2>&1 && certbot certonly --webroot -w /var/www/html -d "$DOMINIO" -m "$CORREO" \
         --agree-tos --no-eff-email --non-interactive --deploy-hook "systemctl reload nginx"; then
      CERT="/etc/letsencrypt/live/$DOMINIO/fullchain.pem"; CLAVE="/etc/letsencrypt/live/$DOMINIO/privkey.pem"
      escribir_nginx; nginx -t && { if [[ $SYSTEMD -eq 1 ]]; then systemctl reload nginx; else nginx -s reload; fi; }
      set_env SGIT_HSTS 1
      [[ $SYSTEMD -eq 1 ]] && systemctl restart sgit-web
      ok "Certificado valido de Let's Encrypt instalado (renovacion automatica) y HSTS activado"
    else
      warn "No se pudo obtener el certificado de Let's Encrypt (el dominio debe apuntar a este servidor y el puerto 80 ser alcanzable desde Internet). Se conserva el autofirmado."
    fi
  fi
else
  log "Se omitio Nginx (--sin-nginx): la web queda sin cifrado en el puerto 8000."
fi
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  if [[ $SIN_NGINX -eq 0 ]]; then ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; ok "Firewall: puertos 80 y 443 abiertos"
  else ufw allow 8000/tcp >/dev/null; ok "Firewall: puerto 8000 abierto"; fi
fi

paso "9/9 Respaldos, comandos y verificacion"
if [[ ! -f "$CONF_DIR/respaldo.key" ]]; then ( umask 077; openssl rand -base64 48 > "$CONF_DIR/respaldo.key" ); ok "Llave de cifrado de respaldos creada"; fi
install -m 755 "$DEST/scripts/respaldo.sh" /usr/local/bin/sgit-respaldo
install -m 755 "$DEST/scripts/probar.sh" /usr/local/bin/sgit-probar
install -m 755 "$DEST/scripts/salud.sh" /usr/local/bin/sgit-salud
install -m 755 "$DEST/scripts/disponibilidad.py" /usr/local/bin/sgit-disponibilidad
cat > /etc/cron.d/sgit-salud <<'EOF'
# Comprobacion de salud del SGIT cada minuto: registra la disponibilidad y reinicia lo que no responda
* * * * * root /usr/local/bin/sgit-salud
EOF
chmod 644 /etc/cron.d/sgit-salud
cat > /etc/logrotate.d/sgit <<'EOF'
/var/log/sgit_salud.log {
    yearly
    rotate 3
    compress
    missingok
    notifempty
}
/var/log/sgit_respaldo.log {
    monthly
    rotate 6
    compress
    missingok
    notifempty
}
EOF
/usr/local/bin/sgit-salud && ok "Monitoreo de salud activo (cada minuto): sgit-disponibilidad muestra el porcentaje real" || warn "La primera comprobacion de salud fallo; revisa los servicios."
cat > /etc/cron.d/sgit-respaldo <<EOF
# Respaldo cifrado diario del SGIT a las 02:30 de la hora del taller ($ZONA); cron corre en la hora del servidor
30 * * * * root [ "\$(TZ=$ZONA date +\\%H)" = "02" ] && /usr/local/bin/sgit-respaldo >> /var/log/sgit_respaldo.log 2>&1
EOF
chmod 644 /etc/cron.d/sgit-respaldo
if /usr/local/bin/sgit-respaldo; then ok "Primer respaldo cifrado creado y verificado en $BACKUP_DIR"
else fail "El respaldo de prueba fallo; revisa el mensaje anterior."; fi

echo
log "Probando las reglas de negocio contra la base (no deja datos)..."
SGIT_ENV="$ENV_FILE" "$DEST/scripts/prueba_reglas_sql.sh" || fail "Alguna regla de negocio fallo. Revisa la salida anterior."

echo
echo -e "${C_OK}=============================== INSTALACION COMPLETA ===============================${C_RESET}"
echo "  Abre en el navegador:   $URL"
if [[ -n "$ADMIN_PW" ]]; then
  echo "  Administrador:          $ADMIN_EMAIL"
  echo "  Contrasena inicial:     $ADMIN_PW   (tambien en $CRED_FILE, solo root)"
fi
echo
echo "  Comandos utiles:"
echo "    sudo sgit-probar              reglas, seguridad y migraciones (seguro, no deja datos)"
echo "    sudo sgit-probar --respaldo   recuperacion a un momento exacto (copia base + WAL)"
echo "    sudo sgit-probar --completo   API y pantallas (crea registros PRUEBA)"
echo "    sudo sgit-respaldo            respaldo cifrado ahora (ya corre solo a las 2:30 hora del taller)"
echo "    sgit-disponibilidad           disponibilidad real (meta: 99 % en horario laboral)"
if [[ $SYSTEMD -eq 1 ]]; then
echo "    systemctl status sgit-api sgit-web      estado de los servicios"
echo "    journalctl -u sgit-api -f               registros de la API"
fi
echo
[[ $SIN_NGINX -eq 0 ]] && warn "El certificado es autofirmado: el navegador avisara una vez. Para uno valido usa tu dominio con Let's Encrypt."
warn "Guarda una copia de $CONF_DIR/respaldo.key fuera del servidor: sin ella los respaldos no se pueden abrir."
if ss -ltn 2>/dev/null | grep -q ':3000 '; then warn "Hay algo escuchando en el puerto 3000 (probablemente el backend NestJS anterior). Puedes detenerlo: ya no se usa."; fi
echo "  Registro completo: $LOG"
exit 0
__SGIT_PAYLOAD_BELOW__
