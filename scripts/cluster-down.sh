#!/usr/bin/env bash
# Destruye el entorno local completo (clúster, LocalStack y recursos de Terraform).
set -euo pipefail
cd "$(dirname "$0")/.."
kind delete cluster --name poc-asr1 || true
docker compose -f infra/local/docker-compose.yml down -v || true
rm -f "${KUBECONFIG_FILE:-$HOME/.kube/poc-asr1.yaml}"
