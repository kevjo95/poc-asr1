#!/usr/bin/env bash
# Destruye todo lo creado en AWS (fase A7 del plan 0002) y verifica que no queden recursos que sigan cobrando.
# Pide confirmación escrita; `terraform destroy` pide además su propia confirmación.
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_PROFILE="${AWS_PROFILE:-poc-asr1}"
TF="infra/envs/aws-eks"; export KUBECONFIG="${KUBECONFIG_AWS:-$HOME/.kube/poc-asr1-aws.yaml}"
echo "Cuenta: $(aws sts get-caller-identity --query Arn --output text)"
read -r -p "Escribe 'destruir' para borrar TODO el entorno de AWS de la PoC: " ok; [ "$ok" = "destruir" ] || { echo "Cancelado."; exit 1; }

echo "[1/3] Quitar el Service LoadBalancer antes del clúster (si no, el NLB queda huérfano y sigue cobrando)"
helm uninstall ingest-ms 2>/dev/null || true
helm uninstall cluster-autoscaler -n kube-system 2>/dev/null || true
for _ in $(seq 1 30); do kubectl get svc ingest-ms >/dev/null 2>&1 || break; sleep 5; done
sleep 30   # el controlador tarda en borrar el balanceador

echo "[2/3] terraform destroy"
terraform -chdir="$TF" destroy

echo "[3/3] Verificación de residuos (todo debe salir vacío o en 0)"
REGION="$(terraform -chdir="$TF" output -raw region 2>/dev/null || echo us-east-1)"
echo "- instancias EC2 activas con la etiqueta del proyecto:"
aws ec2 describe-instances --region "$REGION" --filters Name=tag:project,Values=poc-asr1 Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text
echo "- balanceadores:"; aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerName' --output text 2>/dev/null || true
echo "- volúmenes EBS sin usar:"; aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text
echo "- IP elásticas:"; aws ec2 describe-addresses --region "$REGION" --query 'Addresses[].PublicIp' --output text
echo "- clústeres EKS:"; aws eks list-clusters --region "$REGION" --query 'clusters' --output text
echo "Revisa Cost Explorer mañana para confirmar que el gasto se detuvo."
