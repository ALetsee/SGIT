#!/usr/bin/env bash
# Comprobador de salud del SGIT. Corre cada minuto por cron:
#   - verifica la API (y su base de datos), la web y Nginx
#   - registra OK o FALLO en /var/log/sgit_salud.log (con eso se calcula la disponibilidad)
#   - reinicia el servicio que no responda (maximo una vez cada 5 minutos)
LOG="${SGIT_SALUD_LOG:-/var/log/sgit_salud.log}"
ENV_FILE="${SGIT_ENV:-/etc/sgit/sgit.env}"
[[ -r "$ENV_FILE" ]] && { set -a; . "$ENV_FILE"; set +a; }
WEB="${WEB_BIND:-127.0.0.1:8000}"; WEB="${WEB/0.0.0.0/127.0.0.1}"
fallos=()
curl -fsS -m 5 http://127.0.0.1:8081/salud >/dev/null 2>&1 || fallos+=(api)
curl -fsS -m 5 "http://$WEB/salud" >/dev/null 2>&1 || fallos+=(web)
if [[ -f /etc/nginx/sites-enabled/sgit ]]; then curl -fsSk -m 5 https://127.0.0.1/salud >/dev/null 2>&1 || fallos+=(nginx); fi
ahora="$(date -Is)"
if [[ ${#fallos[@]} -eq 0 ]]; then echo "$ahora OK" >> "$LOG"; exit 0; fi
echo "$ahora FALLO ${fallos[*]}" >> "$LOG"
SELLO=/run/sgit-reinicio.sello
if [[ -d /run/systemd/system && ( ! -f "$SELLO" || -n "$(find "$SELLO" -mmin +5 2>/dev/null)" ) ]]; then
  touch "$SELLO"
  for f in "${fallos[@]}"; do
    case "$f" in api) u=sgit-api;; web) u=sgit-web;; nginx) u=nginx;; esac
    systemctl restart "$u" >/dev/null 2>&1 && echo "$ahora REINICIO $u" >> "$LOG"
  done
fi
exit 1
