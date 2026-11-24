#!/usr/bin/env bash
# Diagnóstico del camino cliente -> pod: misma carga por dos caminos y se compara lo que mide k6 en cada uno.
#  A) NodePort de kind (Docker Desktop -> kube-proxy -> pod)    B) port-forward a UN pod. OJO: el port-forward es un túnel único y se satura solo (hallazgo del 23-nov); útil solo como contraste, no como prueba.
# Uso: RATE=150 DUR=60 ./scripts/path-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/poc-asr1.yaml}"
RATE="${RATE:-150}"; DUR="${DUR:-60}"; OUT="results/summaries/path-check-$(date +%Y%m%d-%H%M%S).txt"
POD=$(kubectl get pod -l app.kubernetes.io/name=ingest-ms -o jsonpath='{.items[0].metadata.name}')
run() {  # $1 etiqueta  $2 base url
  echo "=== $1 ($2) · ${RATE} req/s · ${DUR} s" | tee -a "$OUT"
  k6 run --quiet -e RUN_ID="pc-$1" -e DURATION_S="$DUR" -e BASE_RATE="$RATE" -e BASE_URL="$2" load/p1-base.js 2>&1 \
    | grep -E "fase steady|202|dropped" | tee -a "$OUT" || true
  rm -f "results/summaries/pc-$1.json" "results/summaries/pc-$1-"*; sleep 10
}
run nodeport "http://localhost:8080"
kubectl port-forward "pod/$POD" 18081:8080 >/dev/null 2>&1 & PF=$!; trap 'kill $PF 2>/dev/null || true' EXIT; sleep 3
run directo "http://localhost:18081"
echo "(compara errores y p99 de k6 en ambos caminos; si solo el NodePort falla, el cuello está en el entorno y no en el MS)" | tee -a "$OUT"
