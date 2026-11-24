#!/usr/bin/env bash
# Prueba corta de saturación de UNA réplica a 500 req/s con el generador dentro del clúster.
# Uso: ./scripts/probe-500.sh <etiqueta> [valores de helm...]   (p. ej. --set resources.limits.cpu=2000m)
set -uo pipefail
cd "$(dirname "$0")/.."; source scripts/lib.sh
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/poc-asr1.yaml}"
LABEL="$1"; shift; RATE="${RATE:-500}"; DUR="${DUR:-40}"
helm upgrade ingest-ms deploy/helm/ingest-ms --set hmacSecret=poc-local-secret \
  --set config.queueUrl=http://poc-asr1-localstack:4566/000000000000/poc-asr1-ingest \
  --set config.sqsEndpoint=http://poc-asr1-localstack:4566 --set config.localAwsCredentials=true \
  --set autoscaling.enabled=false --set replicaCount=1 "$@" >/dev/null
kubectl rollout status deploy/ingest-ms --timeout=240s >/dev/null; sleep 25
MAP=$("${AWS[@]}" lambda list-event-source-mappings --function-name "$PREFIX-reconciler" --query 'EventSourceMappings[0].UUID' --output text)
"${AWS[@]}" lambda update-event-source-mapping --uuid "$MAP" --no-enabled >/dev/null
for q in "$QUEUE_NAME" "$DLQ_NAME"; do "${AWS[@]}" sqs purge-queue --queue-url "$(queue_url $q)" >/dev/null 2>&1 || true; done; sleep 3
echo "== $LABEL"
./scripts/k6-incluster.sh up >/dev/null
# precalentamiento breve a 100/s para no medir el arranque en frío
./scripts/k6-incluster.sh run load/p1-base.js "warm-$LABEL" DURATION_S=20 BASE_RATE=100 >/dev/null 2>&1
./scripts/k6-incluster.sh run load/p1-base.js "probe-$LABEL" DURATION_S="$DUR" BASE_RATE="$RATE" 2>&1 | grep -E "fase|202="
POD=$(kubectl get pod -l app.kubernetes.io/name=ingest-ms -o jsonpath='{.items[0].metadata.name}')
echo "reinicios del pod: $(kubectl get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
rm -f results/summaries/probe-"$LABEL"* results/summaries/warm-"$LABEL"*
"${AWS[@]}" lambda update-event-source-mapping --uuid "$MAP" --enabled >/dev/null
