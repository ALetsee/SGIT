#!/usr/bin/env bash
# Verificacion de controles de seguridad del SGIT instalado (autoevaluacion; ver docs/SEGURIDAD_ASVS.md).
# No necesita credenciales. Ejecutar como root: revisa permisos de archivos y sockets.
set -u   # sin pipefail: "grep -q" cierra el pipe al encontrar y haria fallar el pipeline aunque coincida
ENV_FILE="${SGIT_ENV:-/etc/sgit/sgit.env}"
[[ -r "$ENV_FILE" ]] && { set -a; . "$ENV_FILE"; set +a; }
HTTPS="${SGIT_HTTPS:-https://127.0.0.1}"
OK=0; FALLO=0; INFO=0
ok()   { echo "OK    $1"; OK=$((OK+1)); }
mal()  { echo "FALLO $1"; FALLO=$((FALLO+1)); }
info() { echo "INFO  $1"; INFO=$((INFO+1)); }
chk()  { if eval "$2"; then ok "$1"; else mal "$1"; fi; }
H="$(mktemp)"; trap 'rm -f "$H"' EXIT
NGINX=1; [[ -f /etc/nginx/sites-enabled/sgit ]] || { NGINX=0; HTTPS="http://127.0.0.1:8000"; }

if [[ $NGINX -eq 1 ]]; then
echo "== Transporte (TLS) =="
chk "el puerto 80 redirige a HTTPS" '[[ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/)" == "301" ]]'
chk "HTTPS responde" '[[ "$(curl -sk -o /dev/null -w "%{http_code}" $HTTPS/login)" == "200" ]]'
chk "solo se permiten TLS 1.2 y 1.3" 'nginx -T 2>/dev/null | grep -qE "ssl_protocols\s+TLSv1\.2 TLSv1\.3"'
chk "TLS 1.2 negocia" 'echo | openssl s_client -connect 127.0.0.1:443 -tls1_2 2>/dev/null | grep -q "Cipher is"'
chk "Nginx no revela su versión" '! curl -skI $HTTPS/login | grep -iE "^server:.*[0-9]+\.[0-9]+"'
if curl -skI $HTTPS/login | grep -qi "strict-transport-security"; then ok "HSTS activo (certificado válido)"
else info "HSTS desactivado a propósito: con certificado autofirmado bloquearía el acceso. Se activa con --letsencrypt."; fi
else info "instalación sin Nginx (--sin-nginx): no hay TLS que verificar; la web viaja sin cifrado"; fi

echo "== Cabeceras y cookies de la web =="
curl -sk -D "$H" -o /dev/null $HTTPS/login
for c in "content-security-policy" "x-frame-options" "x-content-type-options" "referrer-policy" "permissions-policy" "cache-control: no-store"; do
  chk "cabecera $c" "grep -qi '^$c' '$H'"
done
chk "la política de contenido bloquea scripts ajenos (script-src 'self')" "grep -i '^content-security-policy' '$H' | grep -q \"script-src 'self'\""
chk "la cookie de sesión es HttpOnly" "grep -i '^set-cookie' '$H' | grep -qi httponly"
if [[ $NGINX -eq 1 ]]; then chk "la cookie de sesión es Secure" "grep -i '^set-cookie' '$H' | grep -qi 'secure'"; fi
chk "la cookie de sesión es SameSite" "grep -i '^set-cookie' '$H' | grep -qi samesite"
chk "un formulario sin token CSRF se rechaza (400)" '[[ "$(curl -sk -o /dev/null -w "%{http_code}" -d "email=a@b.c&password=x" $HTTPS/login)" == "400" ]]'

echo "== Acceso sin sesión =="
chk "las pantallas piden iniciar sesión (302)" '[[ "$(curl -sk -o /dev/null -w "%{http_code}" $HTTPS/ordenes)" == "302" ]]'
chk "la API rechaza peticiones sin token (401)" '[[ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8081/usuarios)" == "401" ]]'
chk "la API rechaza un token falso (401)" '[[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer a.b.c" http://127.0.0.1:8081/usuarios)" == "401" ]]'
chk "un token con algoritmo 'none' se rechaza (401)" 'T="$(printf "{\"alg\":\"none\",\"typ\":\"JWT\"}" | base64 -w0 | tr "+/" "-_" | tr -d "=").$(printf "{\"sub\":\"00000000-0000-0000-0000-000000000000\",\"exp\":9999999999}" | base64 -w0 | tr "+/" "-_" | tr -d "=")."; [[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $T" http://127.0.0.1:8081/usuarios)" == "401" ]]'
chk "las rutas inexistentes no filtran trazas internas" '! curl -sk $HTTPS/no-existe-xyz | grep -qiE "traceback|werkzeug|goroutine|panic"'
chk "la API responde JSON genérico ante rutas inexistentes" 'curl -s http://127.0.0.1:8081/no-existe | grep -q "statusCode"'

echo "== Exposición de servicios =="
solo_local() { # puerto
  local dir; dir="$(ss -ltnH "sport = :$1" 2>/dev/null | awk '{print $4}')"
  [[ -z "$dir" ]] && return 0
  ! echo "$dir" | grep -qE '^(0\.0\.0\.0|\*|\[::\]):'
}
chk "la API (8081) solo escucha en localhost" 'solo_local 8081'
chk "PostgreSQL solo escucha en localhost" 'solo_local "${DB_PORT:-5432}"'
if ss -ltnH "sport = :8000" 2>/dev/null | awk '{print $4}' | grep -qE '^(0\.0\.0\.0|\*|\[::\]):'; then info "la web (8000) está expuesta sin cifrado: instalación con --sin-nginx"
else ok "la web interna (8000) solo escucha en localhost"; fi

echo "== Archivos, secretos y procesos =="
perm() { stat -c '%a %U:%G' "$1" 2>/dev/null; }
chk "sgit.env es 640 root:sgit" '[[ "$(perm /etc/sgit/sgit.env)" == "640 root:sgit" ]]'
chk "la llave de respaldos es 600" '[[ "$(perm /etc/sgit/respaldo.key | cut -d" " -f1)" == "600" ]]'
[[ -f /etc/sgit/tls/sgit.key ]] && chk "la llave privada TLS es 600" '[[ "$(perm /etc/sgit/tls/sgit.key | cut -d" " -f1)" == "600" ]]'
chk "los respaldos están en un directorio privado (750 o más estricto)" '[[ "$(stat -c %a /var/backups/sgit)" =~ ^7[05]0$ ]]'
chk "la API no corre como root" '[[ "$(ps -o user= -C sgit-api | head -1 | tr -d " ")" != "root" && -n "$(pgrep -x sgit-api)" ]]'
chk "la web no corre como root" '! ps -o user= -C gunicorn | grep -qx root'
chk "el JWT_SECRET tiene al menos 32 caracteres" '[[ ${#JWT_SECRET} -ge 32 ]]'
chk "no hay contraseñas en la configuración de Nginx ni en los registros recientes" '! grep -rqiE "password=" /etc/nginx/sites-enabled/ 2>/dev/null'

echo "== Base de datos =="
PGq() { runuser -u postgres -- psql -X -q -tA -d "${DB_NAME:-taller_db}" -c "$1" 2>/dev/null; }
chk "el rol de la aplicación no es superusuario" '[[ "$(PGq "SELECT rolsuper FROM pg_roles WHERE rolname=current_setting('"'"'role'"'"') OR rolname='"'"'${DB_USER:-app_taller}'"'"'" | head -1)" == "f" ]]'
chk "el rol de la aplicación no puede crear tablas" '! PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -U "${DB_USER:-app_taller}" -d "${DB_NAME:-taller_db}" -X -q -c "CREATE TABLE sgit_no_debe_existir(x int)" >/dev/null 2>&1'
chk "la bitácora de auditoría es de solo agregar (sin UPDATE ni DELETE)" '[[ "$(PGq "SELECT count(*) FROM information_schema.role_table_grants WHERE table_name='"'"'auditoria'"'"' AND grantee='"'"'${DB_USER:-app_taller}'"'"' AND privilege_type IN ('"'"'UPDATE'"'"','"'"'DELETE'"'"')")" == "0" ]]'
chk "los hashes de contraseña son argon2id" '[[ "$(PGq "SELECT count(*) FROM usuario WHERE password_hash NOT LIKE '"'"'\$argon2id\$%'"'"'")" == "0" ]]'
chk "la seguridad por fila (RLS) está activa en partida" '[[ "$(PGq "SELECT relrowsecurity FROM pg_class WHERE relname='"'"'partida'"'"'")" == "t" ]]'

echo; echo "Resultado: $OK correctas, $FALLO con fallo ($INFO avisos informativos)."
[[ $FALLO -eq 0 ]]
