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
  --expression-attribute-values "{\":s\":{\"S\":\"$1\"}}" --query Count --output text; }
count_all() { "${AWS[@]}" dynamodb scan --table-name "$TABLE_NAME" --select COUNT --query Count --output text; }
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
