#!/usr/bin/env python3
"""Vacía la tabla de idempotencia por lotes (rápido incluso con cientos de miles de filas). Requiere boto3."""
import os, sys, boto3
table = sys.argv[1] if len(sys.argv) > 1 else "poc-asr1-idempotency"
ep = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566") if os.environ.get("USE_AWS") != "1" else None
if ep:  # LocalStack acepta cualquier credencial ficticia
    os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
    os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")
db = boto3.client("dynamodb", region_name="us-east-1", endpoint_url=ep)
n = 0
for page in db.get_paginator("scan").paginate(TableName=table, ProjectionExpression="eventId"):
    items = page["Items"]
    for i in range(0, len(items), 25):
        db.batch_write_item(RequestItems={table: [{"DeleteRequest": {"Key": {"eventId": it["eventId"]}}} for it in items[i:i+25]]})
        n += len(items[i:i+25])
print(f"borradas {n} filas de {table}")
