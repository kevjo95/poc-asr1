import json
import os
import sys

import pytest
from botocore.exceptions import ClientError

os.environ.setdefault("TABLE_NAME", "t")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import handler  # noqa: E402


class FakeDynamo:
    """Implementa solo la semántica condicional que usa el handler."""

    def __init__(self):
        self.items = {}

    def put_item(self, TableName, Item, ConditionExpression, ExpressionAttributeNames,
                 ExpressionAttributeValues, ReturnValues):
        key = Item["eventId"]["S"]
        old = self.items.get(key)
        now = int(ExpressionAttributeValues[":now"]["N"])
        allowed = old is None or (
            old["status"]["S"] == handler.EN_PROCESO and int(old["processingExpiresAt"]["N"]) < now
        )
        if not allowed:
            raise ClientError({"Error": {"Code": "ConditionalCheckFailedException"}}, "PutItem")
        self.items[key] = Item
        return {"Attributes": old} if old else {}

    def update_item(self, TableName, Key, ExpressionAttributeValues, **_):
        key = Key["eventId"]["S"]
        if key not in self.items:
            raise ClientError({"Error": {"Code": "ConditionalCheckFailedException"}}, "UpdateItem")
        self.items[key]["status"] = {"S": handler.COMPLETADO}
        self.items[key]["completedAt"] = ExpressionAttributeValues[":now"]


def rec(event_id, mid=None):
    return {
        "messageId": mid or f"m-{event_id}",
        "body": json.dumps({"eventId": event_id}),
        "messageAttributes": {
            "eventId": {"stringValue": event_id, "dataType": "String"},
            "source": {"stringValue": "argyle", "dataType": "String"},
        },
    }


@pytest.fixture
def fake(monkeypatch):
    f = FakeDynamo()
    monkeypatch.setattr(handler, "_client", f)
    monkeypatch.setattr(handler, "FAILURE_RATE", 0)
    return f


def test_evento_nuevo_queda_completado(fake):
    out = handler.handler({"Records": [rec("e1")]})
    assert out == {"batchItemFailures": []}
    assert fake.items["e1"]["status"]["S"] == handler.COMPLETADO


def test_duplicado_completado_se_descarta_sin_error(fake):
    handler.handler({"Records": [rec("e1")]})
    out = handler.handler({"Records": [rec("e1", "otro-mensaje")]})
    assert out["batchItemFailures"] == []
    assert len(fake.items) == 1


def test_duplicado_en_el_mismo_lote(fake):
    out = handler.handler({"Records": [rec("e1", "a"), rec("e1", "b")]})
    assert out["batchItemFailures"] == []
    assert fake.items["e1"]["status"]["S"] == handler.COMPLETADO


def test_falla_deja_en_proceso_y_se_reporta(fake, monkeypatch):
    monkeypatch.setattr(handler, "FAILURE_RATE", 1.0)
    out = handler.handler({"Records": [rec("e1", "m1")]})
    assert out["batchItemFailures"] == [{"itemIdentifier": "m1"}]
    assert fake.items["e1"]["status"]["S"] == handler.EN_PROCESO


def test_en_proceso_vigente_no_se_reclama(fake, monkeypatch):
    monkeypatch.setattr(handler, "FAILURE_RATE", 1.0)
    handler.handler({"Records": [rec("e1")]})
    monkeypatch.setattr(handler, "FAILURE_RATE", 0)
    out = handler.process_record(fake, rec("e1"), now=1)  # aún dentro de la expiración
    assert out == "duplicate"


def test_en_proceso_vencido_se_reintenta_y_no_es_duplicado(fake, monkeypatch):
    monkeypatch.setattr(handler, "FAILURE_RATE", 1.0)
    handler.handler({"Records": [rec("e1")]})
    monkeypatch.setattr(handler, "FAILURE_RATE", 0)
    far_future = 10**10
    assert handler.process_record(fake, rec("e1"), now=far_future) == "retried"
    assert fake.items["e1"]["status"]["S"] == handler.COMPLETADO


def test_mensaje_sin_event_id_se_reporta_como_falla(fake):
    bad = {"messageId": "x", "body": "{}", "messageAttributes": {}}
    out = handler.handler({"Records": [bad]})
    assert out["batchItemFailures"] == [{"itemIdentifier": "x"}]
