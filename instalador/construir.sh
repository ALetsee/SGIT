#!/usr/bin/env bash
# Arma el instalador autoextraible desde este repositorio:  ./instalador/construir.sh
# Resultado: ./sgit-instalador.sh (cabecera con el instalador + el proyecto empaquetado).
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"
python3 scripts/generar_api_md.py >/dev/null
find . -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
chmod +x scripts/*.sh scripts/*.py
PAQUETE="$(mktemp)"; trap 'rm -f "$PAQUETE"' EXIT
tar --owner=0 --group=0 --numeric-owner -czf "$PAQUETE" backend-go frontend-py database scripts docs
cat instalador/cabecera.sh "$PAQUETE" > sgit-instalador.sh
chmod +x sgit-instalador.sh
echo "Generado $(pwd)/sgit-instalador.sh ($(du -h sgit-instalador.sh | cut -f1))"
