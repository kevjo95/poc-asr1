#!/usr/bin/env bash
# Envía un webhook firmado al MS e imprime "<eventId> <código HTTP>". Uso: send-one.sh <eventId>
source "$(dirname "$0")/lib.sh"
id="$1"; body=$(mk_body "$id")
code=$(post_webhook "${BASE_URL:-http://localhost:8080}" "${SOURCE:-argyle}" "$id" "$body" "sha256=$(sign_body "$body")")
echo "$id $code"
