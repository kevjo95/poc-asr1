#!/usr/bin/env bash
# F3 · Contrato del MS de ingesta: 202 / 400 / 401 / 404 / 503.
# BASE_URL: MS conectado a SQS.  BAD_URL: MS cuyo SQS es inalcanzable (para 503).
source "$(dirname "$0")/lib.sh"
BASE="${BASE_URL:-http://localhost:8080}"; BAD="${BAD_URL:-http://localhost:8081}"
RUN="f3-$(date +%s)"; fail=0
check() { # nombre esperado obtenido
  if [ "$2" = "$3" ]; then echo "OK    $1 -> $3"; else echo "FALLO $1 -> esperado $2, obtenido $3"; fail=1; fi; }
B=$(mk_body "$RUN-1"); S="sha256=$(sign_body "$B")"
check "202 firma y cuerpo válidos"        202 "$(post_webhook "$BASE" argyle "$RUN-1" "$B" "$S")"
check "202 fuente central-payments"       202 "$(post_webhook "$BASE" central-payments "$RUN-1" "$B" "$S")"
check "401 firma inválida"                401 "$(post_webhook "$BASE" argyle "$RUN-1" "$B" "sha256=deadbeef")"
check "401 sin firma"                     401 "$(post_webhook "$BASE" argyle "$RUN-1" "$B" "")"
BAD_JSON='{no es json'
check "400 JSON inválido"                 400 "$(post_webhook "$BASE" argyle "$RUN-2" "$BAD_JSON" "sha256=$(sign_body "$BAD_JSON")")"
MISS='{"eventId":"'"$RUN-3"'","type":"x"}'
check "400 campo obligatorio ausente"     400 "$(post_webhook "$BASE" argyle "$RUN-3" "$MISS" "sha256=$(sign_body "$MISS")")"
check "400 X-Event-Id distinto del cuerpo" 400 "$(post_webhook "$BASE" argyle "otro-id" "$B" "$S")"
check "404 fuente desconocida"            404 "$(post_webhook "$BASE" desconocida "$RUN-1" "$B" "$S")"
B4=$(mk_body "$RUN-4"); check "503 SQS no confirma" 503 "$(post_webhook "$BAD" argyle "$RUN-4" "$B4" "sha256=$(sign_body "$B4")")"
[ "$fail" = 0 ] && echo "RESULTADO: OK" || { echo "RESULTADO: FALLO"; exit 1; }
