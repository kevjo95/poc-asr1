#!/usr/bin/env bash
# F2 · Idempotencia: N eventos únicos + D duplicados -> exactamente N COMPLETADO, colas vacías.
source "$(dirname "$0")/lib.sh"
N="${N:-50}"; D="${D:-10}"
QURL=$(queue_url "$QUEUE_NAME"); DLQURL=$(queue_url "$DLQ_NAME")
purge_all; sleep 2
RUN="f2-$(date +%s)"
for i in $(seq 1 "$N"); do send_event "$RUN-$i"; done
for i in $(seq 1 "$D"); do send_event "$RUN-$i"; done   # duplicados de los primeros D
echo "enviados: $((N + D)) mensajes ($N únicos, $D duplicados)"
for t in $(seq 1 40); do
  visible=$(q_attr "$QURL" ApproximateNumberOfMessages); inflight=$(q_attr "$QURL" ApproximateNumberOfMessagesNotVisible)
  [ "$visible" = "0" ] && [ "$inflight" = "0" ] && [ "$(count_status COMPLETADO)" -ge "$N" ] && break; sleep 3
done
done_n=$(count_status COMPLETADO); inproc=$(count_status EN_PROCESO); total=$(count_all); dlq=$(q_attr "$DLQURL" ApproximateNumberOfMessages)
echo "COMPLETADO=$done_n EN_PROCESO=$inproc filas=$total DLQ=$dlq (esperado: COMPLETADO=$N, EN_PROCESO=0, DLQ=0)"
if [ "$done_n" = "$N" ] && [ "$inproc" = "0" ] && [ "$total" = "$N" ] && [ "$dlq" = "0" ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO"; exit 1; fi
