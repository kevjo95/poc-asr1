#!/usr/bin/env bash
# Lanza el dashboard de monitoreo (solo lectura) en http://localhost:8765. Ejecutar en una terminal aparte.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${TARGET:-local}" = "aws" ]; then   # clúster EKS y servicios reales de AWS (solo lectura)
  export KUBECONFIG="${KUBECONFIG_AWS:-$HOME/.kube/poc-asr1-aws.yaml}" USE_AWS=1 AWS_PROFILE="${AWS_PROFILE:-poc-asr1-tf}" PERIOD="${PERIOD:-3}"
  [ -s "$KUBECONFIG" ] || { echo "Falta $KUBECONFIG: corre primero ./scripts/aws-up.sh"; exit 1; }
fi
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
exec env PORT="$PORT" ${USE_AWS:+USE_AWS=1} .venv/bin/python scripts/dashboard/server.py
