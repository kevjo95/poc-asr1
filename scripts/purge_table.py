#!/usr/bin/env python3
"""Vacía la tabla de idempotencia en paralelo (escaneo por segmentos). Requiere boto3.
En AWS real (USE_AWS=1) usa el perfil de AWS_PROFILE; con una tabla de cientos de miles de filas, el borrado en serie tarda más de una hora."""
import os, sys, threading, boto3
table = sys.argv[1] if len(sys.argv) > 1 else "poc-asr1-idempotency"
aws = os.environ.get("USE_AWS") == "1"
ep = None if aws else os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
if ep:  # LocalStack acepta cualquier credencial ficticia
    os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
    os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")
SEG = int(os.environ.get("PURGE_SEGMENTS", 24 if aws else 4))
sess = boto3.Session(region_name="us-east-1")
done = [0] * SEG

def work(seg):
    db = sess.client("dynamodb", endpoint_url=ep)
    for page in db.get_paginator("scan").paginate(TableName=table, ProjectionExpression="eventId", Segment=seg, TotalSegments=SEG):
        items = page["Items"]
        for i in range(0, len(items), 25):
            req = {table: [{"DeleteRequest": {"Key": {"eventId": it["eventId"]}}} for it in items[i:i + 25]]}
            while req:   # reintenta lo que DynamoDB devuelve sin procesar
                req = db.batch_write_item(RequestItems=req).get("UnprocessedItems") or None
            done[seg] += len(items[i:i + 25])

threads = [threading.Thread(target=work, args=(s,)) for s in range(SEG)]
[t.start() for t in threads]; [t.join() for t in threads]
print(f"borradas {sum(done)} filas de {table}")
