#!/usr/bin/env bash
# Generador de carga DENTRO del clúster: un pod con k6 que ataca el Service del MS (sin Docker Desktop ni el equipo anfitrión de por medio).
# Uso:  k6-incluster.sh up | down | run <archivo.js> <RUN_ID> [VAR=valor ...]
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/poc-asr1.yaml}"
IMG="grafana/k6:${K6_IMAGE_TAG:-1.4.0}"; POD=k6-runner
case "${1:?up|down|run}" in
  up)
    if [ "${K6_TARGET:-kind}" = "aws" ]; then
      # En EKS el pod va al grupo de nodos de carga (con taint) y descarga la imagen pública (multi-arquitectura).
      kubectl get pod $POD >/dev/null 2>&1 || kubectl run $POD --image="$IMG" --restart=Never --labels=app=k6-runner \
        --overrides='{"spec":{"nodeSelector":{"role":"load"},"tolerations":[{"key":"load","operator":"Equal","value":"true","effect":"NoSchedule"}]}}' \
        --command -- sleep infinity >/dev/null
    else
      docker image inspect "$IMG" >/dev/null 2>&1 || docker pull -q "$IMG" >/dev/null
      kind load docker-image "$IMG" --name poc-asr1 >/dev/null
      kubectl get pod $POD >/dev/null 2>&1 || kubectl run $POD --image="$IMG" --image-pull-policy=IfNotPresent --restart=Never \
        --labels=app=k6-runner --command -- sleep infinity >/dev/null
    fi
    kubectl wait --for=condition=Ready pod/$POD --timeout=120s >/dev/null; echo "k6-runner listo" ;;
  down) kubectl delete pod $POD --ignore-not-found >/dev/null; echo "k6-runner eliminado" ;;
  run)
    FILE="$2"; RUN="$3"; shift 3
    kubectl exec $POD -- sh -c 'rm -rf /tmp/w && mkdir -p /tmp/w/results/summaries'
    kubectl cp load $POD:/tmp/w/load >/dev/null
    ENVS=(-e "RUN_ID=$RUN" -e "BASE_URL=${BASE_URL:-http://ingest-ms:8080}"); for kv in "$@"; do ENVS+=(-e "$kv"); done
    set +e; kubectl exec $POD -- sh -c "cd /tmp/w && k6 run ${ENVS[*]} $FILE"; RC=$?; set -e
    kubectl cp $POD:/tmp/w/results/summaries/$RUN.json "results/summaries/$RUN.json" >/dev/null 2>&1 || echo "AVISO: no se encontró el resumen de k6"
    exit $RC ;;
esac
