#!/usr/bin/env bash
# Corre un escenario de carga completo: prepara, mide el clúster, ejecuta k6, concilia y genera el informe.
# Uso: ./scripts/run-scenario.sh p0|p1|p2|p3      (parámetros de k6 por variables de entorno, ver load/*.js)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/poc-asr1.yaml}"
PY="${PY:-python3}"
SC="${1:?uso: run-scenario.sh p0|p1|p2|p3}"
case "$SC" in p0) FILE=load/p0-calibracion.js; BURST_OFFSET=0;; p1) FILE=load/p1-base.js; BURST_OFFSET=0;;
              p2) FILE=load/p2-rafaga.js; BURST_OFFSET="${WARMUP_S:-300}";; p3) FILE=load/p3-estres.js; BURST_OFFSET=0;;
              *) echo "escenario desconocido: $SC"; exit 2;; esac
RUN_ID="$SC-$(date +%Y%m%d-%H%M%S)"; OUT="results/raw/$RUN_ID"; mkdir -p "$OUT" results/summaries
HELM_COMMON=(--set hmacSecret="${INGEST_HMAC_SECRET:-poc-local-secret}"
  --set config.queueUrl=http://poc-asr1-localstack:4566/000000000000/poc-asr1-ingest
  --set config.sqsEndpoint=http://poc-asr1-localstack:4566 --set config.localAwsCredentials=true)
log() { echo "[$(date +%H:%M:%S)] $*"; }

# 1) Estado del MS según el escenario
if [ "$SC" = "p0" ]; then
  log "P0: HPA apagado y 1 réplica fija"
  helm upgrade ingest-ms deploy/helm/ingest-ms "${HELM_COMMON[@]}" --set autoscaling.enabled=false --set replicaCount=1 >/dev/null
  WANT=1
else
  log "$SC: HPA activo; esperando el mínimo de 4 réplicas (la bajada del HPA puede tardar ~5 min)"
  helm upgrade ingest-ms deploy/helm/ingest-ms "${HELM_COMMON[@]}" >/dev/null
  WANT=4
fi
for i in $(seq 1 120); do
  spec=$(kubectl get deploy ingest-ms -o jsonpath='{.spec.replicas}'); ready=$(kubectl get deploy ingest-ms -o jsonpath='{.status.readyReplicas}')
  [ "$spec" = "$WANT" ] && [ "${ready:-0}" = "$WANT" ] && break; sleep 5; done
sleep 20   # que el arranque de la JVM deje de consumir CPU antes de medir

# 2) Aislar el MS: pausar el consumo de la Lambda durante la carga (se reanuda al final)
MAP=$("${AWS[@]}" lambda list-event-source-mappings --function-name "$PREFIX-reconciler" --query 'EventSourceMappings[0].UUID' --output text)
"${AWS[@]}" lambda update-event-source-mapping --uuid "$MAP" --no-enabled >/dev/null
QURL=$(queue_url "$QUEUE_NAME"); DLQURL=$(queue_url "$DLQ_NAME")
# Pre-calentamiento (JIT, pools de conexión) y espera de estabilidad: sin esto el arranque en frío de la JVM (CPU > 150 %)
# dispara el HPA antes de la prueba y el tiempo de escalado medido no tiene sentido (hallazgo del intento 1 de P2).
log "Pre-calentamiento: ${PREWARM_RATE:-40} req/s durante ${PREWARM_S:-90} s"
k6 run --quiet -e RUN_ID="prewarm-$RUN_ID" load/prewarm.js >/dev/null 2>&1 || true
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
log "Consumo de la Lambda en pausa; purgando cola y tabla"
for q in "$QURL" "$DLQURL"; do "${AWS[@]}" sqs purge-queue --queue-url "$q" >/dev/null 2>&1 || true; done
$PY scripts/purge_table.py "$TABLE_NAME"; sleep 3

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
log "k6 $FILE (RUN_ID=$RUN_ID)"
set +e; k6 run -e RUN_ID="$RUN_ID" "$FILE" 2>&1 | tee "$OUT/k6.txt"; K6_RC=${PIPESTATUS[0]}; set -e
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
vis=$(q_attr "$QURL" ApproximateNumberOfMessages); fly=$(q_attr "$QURL" ApproximateNumberOfMessagesNotVisible)
persisted=$(( vis + fly ))
log "Nivel 1: 202=$ACC, mensajes en la cola=$persisted"
"${AWS[@]}" lambda update-event-source-mapping --uuid "$MAP" --enabled >/dev/null
DEADLINE=$(( $(date +%s) + ${DRAIN_TIMEOUT_S:-90} ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  vis2=$(q_attr "$QURL" ApproximateNumberOfMessages); fly2=$(q_attr "$QURL" ApproximateNumberOfMessagesNotVisible)
  [ "$vis2" = "0" ] && [ "$fly2" = "0" ] && break; sleep 5; done
done_n=$(count_status COMPLETADO); inproc=$(count_status EN_PROCESO); dlq=$(q_attr "$DLQURL" ApproximateNumberOfMessages)
rem=$(( $(q_attr "$QURL" ApproximateNumberOfMessages) + $(q_attr "$QURL" ApproximateNumberOfMessagesNotVisible) ))
{ echo "Nivel 1 · 202 contados por k6 = $ACC · mensajes persistidos en SQS = $persisted · diferencia = $(( ACC - persisted ))"
  echo "Nivel 2 · muestra procesada por la Lambda en ${DRAIN_TIMEOUT_S:-90} s: COMPLETADO=$done_n, EN_PROCESO=$inproc, DLQ=$dlq, pendientes en cola=$rem"
  [ "$rem" = "0" ] && echo "         cola drenada por completo: COMPLETADO - 202 = $(( done_n - ACC ))" || echo "         (backlog parcial: LocalStack procesa ~9 msg/s; se espera EN_PROCESO=0 y DLQ=0)"
} | tee "$OUT/reconcile.txt"
cp "$OUT/reconcile.txt" "results/summaries/$RUN_ID-reconcile.txt"

# 6) Informe
$PY scripts/analyze.py "$OUT" > "results/summaries/$RUN_ID-informe.md"
cat "results/summaries/$RUN_ID-informe.md"
