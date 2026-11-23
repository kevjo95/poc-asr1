"""Lambda de conciliación (ASR1 complementario / ASR2).

Consume la cola de ingesta y registra cada evento con una escritura condicional en DynamoDB:
  EN_PROCESO (con expiración)  ->  COMPLETADO
- Duplicado (ya existe y no está vencido) -> se descarta sin error.
- EN_PROCESO vencido (un intento previo falló a mitad) -> se reclama de nuevo, no es un duplicado.
- Si el procesamiento falla, el mensaje se devuelve a la cola (ReportBatchItemFailures).
"""
import json
import logging
import os
import random
import time

import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(logging.INFO)

TABLE_NAME = os.environ.get("TABLE_NAME", "")
PROCESSING_TTL = int(os.environ.get("PROCESSING_TTL_SECONDS", "60"))
RECORD_TTL = int(os.environ.get("RECORD_TTL_SECONDS", str(7 * 24 * 3600)))
FAILURE_RATE = float(os.environ.get("SIMULATED_FAILURE_RATE", "0"))

EN_PROCESO = "EN_PROCESO"
COMPLETADO = "COMPLETADO"

_client = None


def _endpoint():
    url = os.environ.get("AWS_ENDPOINT_URL")
    if url:
        return url
    host = os.environ.get("LOCALSTACK_HOSTNAME")
    if host:
        return f"http://{host}:{os.environ.get('EDGE_PORT', '4566')}"
    return None


def dynamo():
    global _client
    if _client is None:
        _client = boto3.client("dynamodb", endpoint_url=_endpoint())
    return _client


def event_id_of(record):
    attrs = record.get("messageAttributes") or {}
    if "eventId" in attrs:
        return attrs["eventId"].get("stringValue")
    return json.loads(record["body"]).get("eventId")


def claim(client, event_id, source, now):
    """Intenta reclamar el evento. Devuelve 'new', 'retried' o 'duplicate'."""
    try:
        resp = client.put_item(
            TableName=TABLE_NAME,
            Item={
                "eventId": {"S": event_id},
                "status": {"S": EN_PROCESO},
                "processingExpiresAt": {"N": str(now + PROCESSING_TTL)},
                "expiresAt": {"N": str(now + RECORD_TTL)},
                "source": {"S": source or "unknown"},
                "claimedAt": {"N": str(now)},
            },
            ConditionExpression="attribute_not_exists(eventId) OR (#s = :proc AND processingExpiresAt < :now)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":proc": {"S": EN_PROCESO}, ":now": {"N": str(now)}},
            ReturnValues="ALL_OLD",
        )
        return "retried" if resp.get("Attributes") else "new"
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return "duplicate"
        raise


def complete(client, event_id, now):
    client.update_item(
        TableName=TABLE_NAME,
        Key={"eventId": {"S": event_id}},
        UpdateExpression="SET #s = :done, completedAt = :now",
        ConditionExpression="attribute_exists(eventId)",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":done": {"S": COMPLETADO}, ":now": {"N": str(now)}},
    )


def process_record(client, record, now=None):
    now = int(now if now is not None else time.time())
    event_id = event_id_of(record)
    if not event_id:
        raise ValueError("mensaje sin eventId")
    attrs = record.get("messageAttributes") or {}
    source = (attrs.get("source") or {}).get("stringValue")

    outcome = claim(client, event_id, source, now)
    if outcome == "duplicate":
        return outcome

    # Aquí iría el trabajo real; la PoC solo simula fallas para ejercitar el reintento.
    if FAILURE_RATE and random.random() < FAILURE_RATE:
        raise RuntimeError("falla simulada después de marcar EN_PROCESO")

    complete(client, event_id, now)
    return outcome


def handler(event, context=None):
    client = dynamo()
    failures = []
    stats = {"new": 0, "retried": 0, "duplicate": 0}
    for record in event.get("Records", []):
        try:
            stats[process_record(client, record)] += 1
        except Exception:  # noqa: BLE001 - se reporta al lote y se reintenta
            log.exception("fallo procesando messageId=%s", record.get("messageId"))
            failures.append({"itemIdentifier": record["messageId"]})
    log.info(json.dumps({"event": "batch", "stats": stats, "failures": len(failures)}))
    return {"batchItemFailures": failures}
