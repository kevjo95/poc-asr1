#!/usr/bin/env bash
# Experimento: capacidad de UNA réplica según CPU del contenedor (CPUs que ve la JVM) y nivel de log por petición. Generador dentro del clúster.
set -uo pipefail
cd "$(dirname "$0")/.."
export LOADGEN=incluster DRAIN_TIMEOUT_S=5 STABLE_WAIT_S=60
export K6_ENV="STEPS=${STEPS:-7} STEP=${STEP:-100} START_RATE=${START_RATE:-100} STEP_S=${STEP_S:-30}"
run() {  # etiqueta  extras-de-helm
  echo "##### $1 :: $2"; HELM_EXTRA="$2" ./scripts/run-scenario.sh p0 > "results/raw/exp-$1.log" 2>&1
  r=$(ls -t results/summaries/p0-*-informe.md | head -1); cp "$r" "results/summaries/exp-capacidad-$1.md"
  grep -E "^\| s0|Tasa lograda|Capacidad por" "$r"
}
run E0-cpu1-info  "--set resources.limits.cpu=1000m"
run E1-cpu1-warn  "--set resources.limits.cpu=1000m --set config.sendLogLevel=WARN"
run E3-cpu2-info  "--set resources.limits.cpu=2000m"
run E2-cpu2-warn  "--set resources.limits.cpu=2000m --set config.sendLogLevel=WARN"
echo "##### fin"
