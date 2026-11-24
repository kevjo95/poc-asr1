#!/usr/bin/env bash
# Levanta todo el entorno local: LocalStack -> Terraform -> kind -> metrics-server -> MS (Helm).
# Uso: KUBECONFIG_FILE=~/.kube/poc-asr1.yaml ./scripts/cluster-up.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG_FILE:-$HOME/.kube/poc-asr1.yaml}"
# La imagen se compila dentro de Docker (Maven + Java 25 en el Dockerfile): no hace falta un JDK local.
TAG="$(awk '/^  tag:/{gsub(/"/,"",$2); print $2; exit}' deploy/helm/ingest-ms/values.yaml)"   # versión que pide el chart

echo "[1/6] LocalStack";        docker compose -f infra/local/docker-compose.yml up -d
until curl -sf localhost:4566/_localstack/health >/dev/null; do sleep 2; done
echo "[2/6] Terraform local";   (cd infra/envs/local && terraform init -input=false >/dev/null && terraform apply -input=false -auto-approve >/dev/null)
echo "[3/6] Imagen del MS";     docker build -q -t "poc-asr1/ingest-ms:$TAG" services/ingest-ms >/dev/null
echo "[4/6] Clúster kind";      kind get clusters | grep -qx poc-asr1 || kind create cluster --config infra/cluster/kind.yaml --kubeconfig "$KUBECONFIG"
kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
docker network connect kind poc-asr1-localstack 2>/dev/null || true
kind load docker-image "poc-asr1/ingest-ms:$TAG" --name poc-asr1 >/dev/null
echo "[5/6] metrics-server"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml >/dev/null
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null 2>&1 || true
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s >/dev/null
echo "[6/6] MS de ingesta (Helm)"
helm upgrade --install ingest-ms deploy/helm/ingest-ms \
  --set hmacSecret="${INGEST_HMAC_SECRET:-poc-local-secret}" \
  --set config.queueUrl=http://poc-asr1-localstack:4566/000000000000/poc-asr1-ingest \
  --set config.sqsEndpoint=http://poc-asr1-localstack:4566 \
  --set config.localAwsCredentials=true >/dev/null
kubectl rollout status deploy/ingest-ms --timeout=300s
echo "Listo. MS en http://localhost:8080  ·  KUBECONFIG=$KUBECONFIG"
