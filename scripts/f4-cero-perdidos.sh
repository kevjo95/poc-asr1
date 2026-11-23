#!/usr/bin/env bash
# F4 · 0 perdidos de punta a punta: cada 202 del MS debe terminar COMPLETADO en la tabla de idempotencia.
source "$(dirname "$0")/lib.sh"
N="${N:-500}"; PAR="${PAR:-20}"
QURL=$(queue_url "$QUEUE_NAME"); DLQURL=$(queue_url "$DLQ_NAME")
purge_all; sleep 2
RUN="f4-$(date +%s)"; OUT=$(mktemp)
start=$(date +%s)
seq 1 "$N" | sed "s/^/$RUN-/" | xargs -P "$PAR" -n 1 "$(dirname "$0")/send-one.sh" > "$OUT"
sent_s=$(( $(date +%s) - start ))
ok=$(awk '$2==202' "$OUT" | wc -l | tr -d ' '); other=$(awk '$2!=202' "$OUT" | wc -l | tr -d ' ')
for t in $(seq 1 60); do
  [ "$(count_status COMPLETADO)" -ge "$ok" ] && break; sleep 2; done
done_n=$(count_status COMPLETADO); inproc=$(count_status EN_PROCESO); dlq=$(q_attr "$DLQURL" ApproximateNumberOfMessages)
lost=$(( ok - done_n ))
echo "enviados=$N en ${sent_s}s (paralelismo $PAR) · 202=$ok · otros códigos=$other"
echo "COMPLETADO=$done_n EN_PROCESO=$inproc DLQ=$dlq · diferencia (202 - COMPLETADO) = $lost"
rm -f "$OUT"
if [ "$lost" = "0" ] && [ "$inproc" = "0" ] && [ "$dlq" = "0" ] && [ "$other" = "0" ]; then echo "RESULTADO: OK (0 perdidos)"; else echo "RESULTADO: FALLO"; exit 1; fi
