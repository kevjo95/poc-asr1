#!/usr/bin/env bash
# Despliega el MS en el EKS ya creado con Terraform (fase A3 del plan 0002). NO crea la infraestructura: eso es `terraform apply`
# en infra/envs/aws-eks, que requiere confirmación explícita.
# Requisitos: perfil SSO activo (aws sso login --profile poc-asr1), docker, helm, kubectl.
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_PROFILE="${AWS_PROFILE:-poc-asr1}"
TF="infra/envs/aws-eks"
out() { terraform -chdir="$TF" output -raw "$1"; }

echo "[0/6] Identidad (debe ser tu cuenta PERSONAL):"; aws sts get-caller-identity --query Arn --output text
read -r -p "¿Es la cuenta personal correcta? (si/no) " ok; [ "$ok" = "si" ] || { echo "Cancelado."; exit 1; }

REGION="$(out region)"; CLUSTER="$(out cluster_name)"; ECR="$(out ecr_repository_url)"
QUEUE_URL="$(out queue_url)"; INGEST_ROLE="$(out ingest_role_arn)"; CA_ROLE="$(out autoscaler_role_arn)"
export KUBECONFIG="${KUBECONFIG_AWS:-$HOME/.kube/poc-asr1-aws.yaml}"   # no toca ~/.kube/config
TAG="$(awk '/^  tag:/{gsub(/"/,"",$2); print $2; exit}' deploy/helm/ingest-ms/values.yaml)"

echo "[1/6] kubeconfig";  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --kubeconfig "$KUBECONFIG" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null

echo "[2/6] Imagen arm64 -> ECR (los nodos son Graviton)"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ECR%%/*}" >/dev/null
docker build -q --platform linux/arm64 -t "$ECR:$TAG" services/ingest-ms >/dev/null
docker push -q "$ECR:$TAG" >/dev/null

echo "[3/6] metrics-server"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml >/dev/null
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s >/dev/null

echo "[4/6] Cluster Autoscaler (CA_IMAGE_TAG debe coincidir con la versión menor de Kubernetes del clúster, p. ej. v1.XX.0)"
helm repo add autoscaler https://kubernetes.github.io/autoscaler >/dev/null 2>&1 || true; helm repo update >/dev/null
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system \
  --set autoDiscovery.clusterName="$CLUSTER" --set awsRegion="$REGION" \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set "rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$CA_ROLE" \
  --set extraArgs.balance-similar-node-groups=true --set extraArgs.skip-nodes-with-system-pods=false \
  ${CA_IMAGE_TAG:+--set image.tag="$CA_IMAGE_TAG"} >/dev/null

echo "[5/6] MS de ingesta"
SECRET="${INGEST_HMAC_SECRET:-$(openssl rand -hex 16)}"
helm upgrade --install ingest-ms deploy/helm/ingest-ms -f deploy/helm/ingest-ms/values-aws.yaml \
  --set image.repository="$ECR" --set image.tag="$TAG" --set config.queueUrl="$QUEUE_URL" --set config.region="$REGION" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$INGEST_ROLE" --set hmacSecret="$SECRET" >/dev/null
kubectl rollout status deploy/ingest-ms --timeout=600s

echo "[6/6] Balanceador interno (NLB)"
for _ in $(seq 1 60); do LB="$(kubectl get svc ingest-ms -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"; [ -n "$LB" ] && break; sleep 5; done
echo "Listo. NLB interno: ${LB:-pendiente} (solo alcanzable desde dentro de la VPC: usa el generador k6 del clúster)"
if [ -z "${INGEST_HMAC_SECRET:-}" ]; then echo "Secreto HMAC generado para esta sesión: $SECRET  (no lo guardes en el repositorio; expórtalo como INGEST_HMAC_SECRET para repetir despliegues)"; fi
echo "KUBECONFIG=$KUBECONFIG"
