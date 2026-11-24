#!/usr/bin/env bash
# Captura el dashboard cada INTERVAL s mientras corra run-scenario.sh <escenario>; guarda PNG y el JSON final del dashboard.
set -uo pipefail
SC="${1:?uso: capture-evidence.sh p0|p1|p2|p3}"; INTERVAL="${INTERVAL:-30}"; URL="${URL:-http://localhost:8765/}"
OUT="results/evidence/$SC"; mkdir -p "$OUT"; T0=$(date +%s)
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
while pgrep -f "run-scenario.sh $SC" >/dev/null; do
  t=$(( $(date +%s) - T0 )); f=$(printf "%s/%s-t%04ds.png" "$OUT" "$SC" "$t")
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1500,1500 --virtual-time-budget=5000 --screenshot="$f" "$URL" >/dev/null 2>&1
  sleep "$INTERVAL"
done
curl -s "${URL}api/state" > "$OUT/$SC-dashboard-final.json"
echo "capturas en $OUT"
