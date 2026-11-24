#!/usr/bin/env bash
# Corre un escenario de carga completo: prepara, mide el clúster, ejecuta k6, concilia y genera el informe.
# Uso: ./scripts/run-scenario.sh p0|p1|p2|p3      (parámetros de k6 por variables de entorno, ver load/*.js)
set -euo pipefail
cd "$(dirname "$0")/.."
# TARGET=aws: EKS + servicios reales (Lambda ACTIVA durante la carga, conciliación con CloudWatch). Por defecto: kind + LocalStack.
if [ "${TARGET:-local}" = "aws" ]; then
  export USE_AWS=1 AWS_PROFILE="${AWS_PROFILE:-poc-asr1-tf}" K6_TARGET=aws LOADGEN=incluster
  export KUBECONFIG="${KUBECONFIG_AWS:-$HOME/.kube/poc-asr1-aws.yaml}"
  [ -n "${INGEST_HMAC_SECRET:-}" ] || { echo "Exporta INGEST_HMAC_SECRET (el que mostró aws-up.sh)"; exit 2; }
  export K6_ENV="${K6_ENV:-} HMAC_SECRET=$INGEST_HMAC_SECRET"
fi
source scripts/lib.sh
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/poc-asr1.yaml}"
PY="${PY:-python3}"
SC="${1:?uso: run-scenario.sh p0|p1|p2|p3}"
case "$SC" in p0) FILE=load/p0-calibracion.js; BURST_OFFSET=0;; p1) FILE=load/p1-base.js; BURST_OFFSET=0;;
              p2) FILE=load/p2-rafaga.js; BURST_OFFSET="${WARMUP_S:-300}";; p3) FILE=load/p3-estres.js; BURST_OFFSET=0;;
              *) echo "escenario desconocido: $SC"; exit 2;; esac
RUN_ID="$SC-$(date +%Y%m%d-%H%M%S)"; OUT="results/raw/$RUN_ID"; mkdir -p "$OUT" results/summaries
if [ "${TARGET:-local}" = "aws" ]; then HELM_COMMON=(--reuse-values)   # el despliegue de aws-up.sh ya trae imagen, cola y rol IRSA
else HELM_COMMON=(--set hmacSecret="${INGEST_HMAC_SECRET:-poc-local-secret}"
  --set config.queueUrl=http://poc-asr1-localstack:4566/000000000000/poc-asr1-ingest
  --set config.sqsEndpoint=http://poc-asr1-localstack:4566 --set config.localAwsCredentials=true); fi
read -r -a HELM_EXTRA_ARR <<< "${HELM_EXTRA:-}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

# 1) Estado del MS según el escenario
if [ "$SC" = "p0" ]; then
  log "P0: HPA apagado y 1 réplica fija"
  helm upgrade ingest-ms deploy/helm/ingest-ms "${HELM_COMMON[@]}" --set autoscaling.enabled=false --set replicaCount=1 ${HELM_EXTRA_ARR[@]+"${HELM_EXTRA_ARR[@]}"} >/dev/null
  WANT=1
else
  log "$SC: HPA activo; esperando el mínimo de 4 réplicas (la bajada del HPA puede tardar ~5 min)"
  helm upgrade ingest-ms deploy/helm/ingest-ms "${HELM_COMMON[@]}" ${HELM_EXTRA_ARR[@]+"${HELM_EXTRA_ARR[@]}"} >/dev/null
  WANT=4
fi
for i in $(seq 1 120); do
  spec=$(kubectl get deploy ingest-ms -o jsonpath='{.spec.replicas}'); ready=$(kubectl get deploy ingest-ms -o jsonpath='{.status.readyReplicas}')
  [ "$spec" = "$WANT" ] && [ "${ready:-0}" = "$WANT" ] && break; sleep 5; done
sleep 20   # que el arranque de la JVM deje de consumir CPU antes de medir

# 2) Aislar el MS: pausar el consumo de la Lambda durante la carga (se reanuda al final)
MAP=$("${AWS[@]}" lambda list-event-source-mappings --function-name "$PREFIX-reconciler" --query 'EventSourceMappings[0].UUID' --output text)
[ "${TARGET:-local}" = "aws" ] || "${AWS[@]}" lambda update-event-source-mapping --uuid "$MAP" --no-enabled >/dev/null
QURL=$(queue_url "$QUEUE_NAME"); DLQURL=$(queue_url "$DLQ_NAME")
# Pre-calentamiento (JIT, pools de conexión) y espera de estabilidad: sin esto el arranque en frío de la JVM (CPU > 150 %)
# dispara el HPA antes de la prueba y el tiempo de escalado medido no tiene sentido (hallazgo del intento 1 de P2).
log "Pre-calentamiento: ${PREWARM_RATE:-40} req/s durante ${PREWARM_S:-90} s"
if [ "${LOADGEN:-host}" = "incluster" ]; then ./scripts/k6-incluster.sh up >/dev/null; ./scripts/k6-incluster.sh run load/prewarm.js "prewarm-$RUN_ID" >/dev/null 2>&1 || true
else k6 run --quiet -e RUN_ID="prewarm-$RUN_ID" load/prewarm.js >/dev/null 2>&1 || true; fi
rm -f "results/summaries/prewarm-$RUN_ID.json"
if [ "$SC" != "p0" ]; then
  log "Esperando que el HPA se estabilice en $WANT réplicas con CPU < 60 % (máx ${STABLE_WAIT_S:-900} s)"
  ok=0; DL=$(( $(date +%s) + ${STABLE_WAIT_S:-900} ))
  while [ "$(date +%s)" -lt "$DL" ]; do
    h=$(kubectl get hpa ingest-ms -o jsonpath='{.status.currentReplicas},{.status.desiredReplicas},{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || echo ",,")
    cur=${h%%,*}; rest=${h#*,}; des=${rest%%,*}; cpu=${rest#*,}
    if [ "$cur" = "$WANT" ] && [ "$des" = "$WANT" ] && [ "${cpu:-100}" -lt 60 ]; then ok=$((ok+1)); else ok=0; fi
    [ "$ok" -ge 6 ] && break; sleep 5; done
  [ "$ok" -ge 6 ] && log "HPA estable en $WANT réplicas" || log "AVISO: el HPA no se estabilizó en $WANT; el escalado de la prueba puede no ser representativo"
fi
[ "${TARGET:-local}" = "aws" ] && log "Lambda ACTIVA durante la carga (AWS); purgando cola y tabla" || log "Consumo de la Lambda en pausa; purgando cola y tabla"
for q in "$QURL" "$DLQURL"; do "${AWS[@]}" sqs purge-queue --queue-url "$q" >/dev/null 2>&1 || true; done
$PY scripts/purge_table.py "$TABLE_NAME"; sleep 3
[ "${TARGET:-local}" = "aws" ] && sleep 60   # SQS exige 60 s tras un purge antes de aceptar mensajes de forma fiable

# 3) Muestreo del clúster en segundo plano
echo "epoch,spec,ready,available,hpa_current,hpa_desired,hpa_cpu_pct" > "$OUT/replicas.csv"
echo "epoch,cpu_millicores_total,cpu_millicores_max,pods" > "$OUT/cpu.csv"
( while true; do
    d=$(kubectl get deploy ingest-ms -o jsonpath='{.spec.replicas},{.status.readyReplicas},{.status.availableReplicas}' 2>/dev/null || echo ",,")
    h=$(kubectl get hpa ingest-ms -o jsonpath='{.status.currentReplicas},{.status.desiredReplicas},{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || echo ",,")
    echo "$(date +%s),$d,$h" >> "$OUT/replicas.csv"; sleep 5; done ) &
SAMP1=$!
( while true; do
    kubectl top pods --no-headers 2>/dev/null | awk -v t="$(date +%s)" '{gsub("m","",$2); s+=$2; if($2>m)m=$2; n++} END{if(n)print t","s","m","n}' >> "$OUT/cpu.csv"; sleep 10; done ) &
SAMP2=$!
trap 'kill $SAMP1 $SAMP2 2>/dev/null || true; "${AWS[@]}" lambda update-event-source-mapping --uuid "$MAP" --enabled >/dev/null 2>&1 || true' EXIT

# 4) Carga
START=$(date +%s)
echo "{\"scenario\":\"$SC\",\"run_id\":\"$RUN_ID\",\"k6_start\":$START,\"burst_offset_s\":$BURST_OFFSET}" > "$OUT/meta.json"
echo "{\"scenario\":\"$SC\",\"start\":$START}" > results/raw/.current-scenario   # lo lee el dashboard
if [ "${TARGET:-local}" = "aws" ] && [ "${VIA_NLB:-1}" = "1" ]; then   # camino real: NLB interno -> pods
  LB=$(kubectl get svc ingest-ms -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'); export BASE_URL="http://$LB:8080"; log "Destino: NLB interno"; fi
log "k6 $FILE (RUN_ID=$RUN_ID)"
if [ "${LOADGEN:-host}" = "incluster" ]; then
  set +e; ./scripts/k6-incluster.sh run "$FILE" "$RUN_ID" ${K6_ENV:-} 2>&1 | tee "$OUT/k6.txt"; K6_RC=${PIPESTATUS[0]}; set -e
else set +e; k6 run -e RUN_ID="$RUN_ID" "$FILE" 2>&1 | tee "$OUT/k6.txt"; K6_RC=${PIPESTATUS[0]}; set -e; fi
rm -f results/raw/.current-scenario
END=$(date +%s); sed -i '' "s/}\$/,\"k6_end\":$END,\"k6_exit\":$K6_RC}/" "$OUT/meta.json"
sleep 10; kill $SAMP1 $SAMP2 2>/dev/null || true
kubectl get pods -o json > "$OUT/pods.json"; kubectl get events --sort-by=.lastTimestamp > "$OUT/events.txt" 2>&1 || true

# 5) Conciliación en dos niveles
# Nivel 1 (la medida del ASR1): todo 202 está persistido en SQS. La Lambda sigue en pausa, así que la cola
#   debe contener exactamente los 202 (en AWS: NumberOfMessagesSent de CloudWatch).
# Nivel 2: se reanuda la Lambda un tiempo acotado y se verifica que lo procesado queda COMPLETADO, sin DLQ ni EN_PROCESO
#   atascados. LocalStack procesa ~9 msg/s, por lo que no se drena todo en las corridas grandes.
ACC=$($PY -c "import json;print(int(json.load(open('results/summaries/$RUN_ID.json'))['metrics']['webhook_accepted']['values']['count']))")
sleep 3
if [ "${TARGET:-local}" = "aws" ]; then
  # Nivel 1 en AWS: NumberOfMessagesSent de CloudWatch (métrica por minuto, aparece con 1-3 min de retraso).
  QN="$QUEUE_NAME"; log "Nivel 1: esperando a CloudWatch (hasta ${CW_WAIT_S:-240} s)"; persisted=0
  for _ in $(seq 1 $(( ${CW_WAIT_S:-240} / 30 ))); do
    sleep 30
    persisted=$("${AWS[@]}" cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name NumberOfMessagesSent \
      --dimensions Name=QueueName,Value="$QN" --start-time "$(date -u -r $((START-120)) +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u -r $((END+120)) +%Y-%m-%dT%H:%M:%SZ)" \
      --period 60 --statistics Sum --query 'sum(Datapoints[].Sum)' --output text | cut -d. -f1)
    [ "${persisted:-0}" -ge "$ACC" ] && break
  done
  DEADLINE=$(( $(date +%s) + ${DRAIN_TIMEOUT_S:-300} ))   # la Lambda sigue activa: esperar a que drene
  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    vis2=$(q_attr "$QURL" ApproximateNumberOfMessages); fly2=$(q_attr "$QURL" ApproximateNumberOfMessagesNotVisible)
    [ "$vis2" = "0" ] && [ "$fly2" = "0" ] && break; sleep 10; done
else
  vis=$(q_attr "$QURL" ApproximateNumberOfMessages); fly=$(q_attr "$QURL" ApproximateNumberOfMessagesNotVisible)
  persisted=$(( vis + fly ))
  log "Nivel 1: 202=$ACC, mensajes en la cola=$persisted"
  "${AWS[@]}" lambda update-event-source-mapping --uuid "$MAP" --enabled >/dev/null
  DEADLINE=$(( $(date +%s) + ${DRAIN_TIMEOUT_S:-90} ))
  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    vis2=$(q_attr "$QURL" ApproximateNumberOfMessages); fly2=$(q_attr "$QURL" ApproximateNumberOfMessagesNotVisible)
    [ "$vis2" = "0" ] && [ "$fly2" = "0" ] && break; sleep 5; done
fi
done_n=$(count_status COMPLETADO); inproc=$(count_status EN_PROCESO); dlq=$(q_attr "$DLQURL" ApproximateNumberOfMessages)
rem=$(( $(q_attr "$QURL" ApproximateNumberOfMessages) + $(q_attr "$QURL" ApproximateNumberOfMessagesNotVisible) ))
{ echo "Nivel 1 · 202 contados por k6 = $ACC · mensajes persistidos en SQS = $persisted · diferencia = $(( ACC - persisted ))"
  echo "Nivel 2 · procesado por la Lambda: COMPLETADO=$done_n, EN_PROCESO=$inproc, DLQ=$dlq, pendientes en cola=$rem"
  [ "$rem" = "0" ] && echo "         cola drenada por completo: COMPLETADO - 202 = $(( done_n - ACC ))" || echo "         (backlog parcial; se espera EN_PROCESO=0 y DLQ=0)"
} | tee "$OUT/reconcile.txt"
cp "$OUT/reconcile.txt" "results/summaries/$RUN_ID-reconcile.txt"

# 6) Informe
for kv in ${K6_ENV:-}; do export "$kv"; done   # el análisis necesita los mismos parámetros que k6 (STEP_S, etc.)
$PY scripts/analyze.py "$OUT" > "results/summaries/$RUN_ID-informe.md"
cat "results/summaries/$RUN_ID-informe.md"
