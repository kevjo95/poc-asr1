#!/usr/bin/env bash
# Lanza el dashboard de monitoreo (solo lectura) en http://localhost:8765. Ejecutar en una terminal aparte.
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/poc-asr1.yaml}"
if [ ! -s "$KUBECONFIG" ]; then   # genera un kubeconfig propio sin tocar ~/.kube/config
  mkdir -p "$(dirname "$KUBECONFIG")"; kind export kubeconfig --name poc-asr1 --kubeconfig "$KUBECONFIG"
fi
if [ ! -x .venv/bin/python ]; then
  echo "Creando entorno Python (.venv) con boto3 (solo la primera vez)…"
  python3 -m venv .venv && .venv/bin/pip install -q boto3
fi
PORT="${PORT:-8765}"
( sleep 2; command -v open >/dev/null && open "http://localhost:$PORT" ) &
exec env PORT="$PORT" .venv/bin/python scripts/dashboard/server.py
