#!/usr/bin/env bash
# Utilidades comunes. Por defecto apunta a LocalStack; para AWS exportar USE_AWS=1 y AWS_PROFILE.
set -euo pipefail
if [ "${USE_AWS:-0}" = "1" ]; then
  AWS=(aws)
else
  export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
  AWS=(aws --endpoint-url "${LOCALSTACK_ENDPOINT:-http://localhost:4566}")
fi
PREFIX="${PREFIX:-poc-asr1}"
QUEUE_NAME="$PREFIX-ingest"; DLQ_NAME="$PREFIX-ingest-dlq"; TABLE_NAME="$PREFIX-idempotency"
queue_url() { "${AWS[@]}" sqs get-queue-url --queue-name "$1" --query QueueUrl --output text; }
q_attr()    { "${AWS[@]}" sqs get-queue-attributes --queue-url "$1" --attribute-names "$2" --query "Attributes.$2" --output text; }
count_status() { "${AWS[@]}" dynamodb scan --table-name "$TABLE_NAME" --select COUNT \
  --filter-expression "#s = :s" --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values "{\":s\":{\"S\":\"$1\"}}" --output json | python3 -c "import sys,json;print(json.load(sys.stdin)['Count'])"; }   # en JSON el CLI suma las páginas (en text imprime una cifra por página)
count_all() { "${AWS[@]}" dynamodb scan --table-name "$TABLE_NAME" --select COUNT --output json | python3 -c "import sys,json;print(json.load(sys.stdin).get('Count',0))"; }
purge_all() {
  for q in "$QUEUE_NAME" "$DLQ_NAME"; do "${AWS[@]}" sqs purge-queue --queue-url "$(queue_url "$q")" >/dev/null 2>&1 || true; done
  for id in $("${AWS[@]}" dynamodb scan --table-name "$TABLE_NAME" --projection-expression eventId --query 'Items[].eventId.S' --output text); do
    "${AWS[@]}" dynamodb delete-item --table-name "$TABLE_NAME" --key "{\"eventId\":{\"S\":\"$id\"}}"; done
}
send_event() { # $1 eventId  $2 source
  "${AWS[@]}" sqs send-message --queue-url "$QURL" \
    --message-body "{\"eventId\":\"$1\",\"type\":\"deposit.settled\"}" \
    --message-attributes "{\"eventId\":{\"DataType\":\"String\",\"StringValue\":\"$1\"},\"source\":{\"DataType\":\"String\",\"StringValue\":\"${2:-argyle}\"}}" >/dev/null
}

# --- helpers para hablar con el MS de ingesta ---
HMAC_SECRET="${INGEST_HMAC_SECRET:-poc-local-secret}"
sign_body() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$HMAC_SECRET" -hex | awk '{print $NF}'; }
mk_body() { # $1 eventId
  printf '{"eventId":"%s","type":"deposit.settled","occurredAt":"2026-12-01T13:00:00Z","accountId":"acc_1","amount":{"value":1250.75,"currency":"USD"}}' "$1"; }
post_webhook() { # $1 base  $2 source  $3 eventId-header  $4 body  $5 signature(header value, vacío = sin header)
  local args=(-s -o /dev/null -w '%{http_code}' -X POST "$1/webhooks/$2" -H 'Content-Type: application/json' --data-binary "$4")
  [ -n "$3" ] && args+=(-H "X-Event-Id: $3")
  [ -n "$5" ] && args+=(-H "X-Signature: $5")
  curl "${args[@]}"
}
