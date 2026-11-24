import json, uuid

def lines(s): return s.strip("\n").split("\n")

PRE = lines(r"""
// Firma HMAC automática. El modo de cada petición se indica con el header marcador X-Test-Mode:
// valid (por defecto) | bad-sig | no-sig | dup | id-mismatch
const mode = pm.request.headers.get('X-Test-Mode') || 'valid';
pm.request.headers.remove('X-Test-Mode');

let id = 'pm-' + Date.now() + '-' + Math.floor(Math.random() * 1e6);
if (mode === 'dup') {
  if (!pm.collectionVariables.get('dupId')) { pm.collectionVariables.set('dupId', id); }
  id = pm.collectionVariables.get('dupId');
}
pm.variables.set('eventId', id);

const cjs = require('crypto-js');
const raw = pm.request.body && pm.request.body.raw ? pm.variables.replaceIn(pm.request.body.raw) : '';
const secret = pm.environment.get('hmacSecret') || pm.collectionVariables.get('hmacSecret');
const hex = cjs.HmacSHA256(raw, secret).toString(cjs.enc.Hex);

if (pm.request.url.getPath().startsWith('/webhooks/')) {
  if (mode === 'no-sig') { pm.request.headers.remove('X-Signature'); }
  else if (mode === 'bad-sig') { pm.request.headers.upsert({ key: 'X-Signature', value: 'sha256=deadbeef' }); }
  else { pm.request.headers.upsert({ key: 'X-Signature', value: 'sha256=' + hex }); }
  if (mode === 'id-mismatch') { pm.request.headers.upsert({ key: 'X-Event-Id', value: 'otro-id' }); }
}
""")

VALID_BODY = '{"eventId":"{{eventId}}","type":"deposit.settled","occurredAt":"2026-12-01T13:00:00Z","accountId":"acc_1","amount":{"value":1250.75,"currency":"USD"}}'

def hdr(mode=None, with_event=True):
    h = [{"key": "Content-Type", "value": "application/json"}]
    if with_event: h.append({"key": "X-Event-Id", "value": "{{eventId}}"})
    h.append({"key": "X-Signature", "value": "placeholder"})   # lo reemplaza el pre-request
    if mode: h.append({"key": "X-Test-Mode", "value": mode})
    return h

def webhook(name, source, expect, body=VALID_BODY, mode=None, extra_test="", remember=False, desc=""):
    test = ["pm.test('Estado %d', () => pm.response.to.have.status(%d));" % (expect, expect)]
    if remember:
        test.append("pm.collectionVariables.set('lastEventId', pm.variables.get('eventId'));")
    if expect == 202:
        test.append("pm.test('Devuelve el eventId', () => pm.expect(pm.response.json().eventId).to.eql(pm.variables.get('eventId')));")
    if extra_test: test += lines(extra_test)
    return {
        "name": name,
        "event": [{"listen": "test", "script": {"type": "text/javascript", "exec": test}}],
        "request": {
            "method": "POST", "header": hdr(mode),
            "body": {"mode": "raw", "raw": body, "options": {"raw": {"language": "json"}}},
            "url": {"raw": "{{baseUrl}}/webhooks/" + source, "host": ["{{baseUrl}}"], "path": ["webhooks", source]},
            "description": desc,
        },
    }

def get_item(name, id_var, expected_status_note):
    pre = lines("""
// Espera a que la Lambda procese el evento (reintenta la misma petición hasta 10 veces).
const n = parseInt(pm.collectionVariables.get('poll_%s') || '0');
if (n > 0) { setTimeout(() => {}, 1500); }
""" % id_var)
    test = lines("""
const body = pm.response.json();
const estado = body.Item && body.Item.status ? body.Item.status.S : null;
const key = 'poll_%(v)s';
const n = parseInt(pm.collectionVariables.get(key) || '0');
if (estado !== 'COMPLETADO' && n < 10) {
  pm.collectionVariables.set(key, String(n + 1));
  pm.execution.setNextRequest(pm.info.requestName);
} else {
  pm.collectionVariables.unset(key);
  pm.test('El evento quedó COMPLETADO en la tabla de idempotencia', () => pm.expect(estado).to.eql('COMPLETADO'));
}
""" % {"v": id_var})
    return {
        "name": name,
        "event": [{"listen": "prerequest", "script": {"type": "text/javascript", "exec": pre}},
                  {"listen": "test", "script": {"type": "text/javascript", "exec": test}}],
        "request": {
            "method": "POST",
            "header": [
                {"key": "Content-Type", "value": "application/x-amz-json-1.0"},
                {"key": "X-Amz-Target", "value": "DynamoDB_20120810.GetItem"},
                {"key": "Authorization", "value": "AWS4-Hmac-SHA256 Credential=test/20260101/us-east-1/dynamodb/aws4_request, SignedHeaders=host, Signature=x"},
            ],
            "body": {"mode": "raw", "raw": '{"TableName":"{{tableName}}","Key":{"eventId":{"S":"{{%s}}"}}}' % id_var},
            "url": {"raw": "{{localstackUrl}}/", "host": ["{{localstackUrl}}"], "path": [""]},
            "description": expected_status_note,
        },
    }

def get(name, path, tests, desc=""):
    return {"name": name,
            "event": [{"listen": "test", "script": {"type": "text/javascript", "exec": tests}}],
            "request": {"method": "GET", "header": [],
                        "url": {"raw": "{{baseUrl}}" + path, "host": ["{{baseUrl}}"], "path": path.strip("/").split("/")},
                        "description": desc}}

folders = [
 {"name": "01 · Salud y métricas", "item": [
   get("Salud (readiness)", "/actuator/health/readiness",
       ["pm.test('Estado 200', () => pm.response.to.have.status(200));",
        "pm.test('Status UP', () => pm.expect(pm.response.json().status).to.eql('UP'));"]),
   get("Salud (liveness)", "/actuator/health/liveness",
       ["pm.test('Estado 200', () => pm.response.to.have.status(200));"]),
 ]},
 {"name": "02 · Caminos felices (202)", "item": [
   webhook("202 · argyle", "argyle", 202, remember=True, desc="Firma y cuerpo válidos. Debe confirmar solo después de persistir en SQS."),
   webhook("202 · central-payments", "central-payments", 202, remember=False),
 ]},
 {"name": "03 · Verificación de procesamiento (LocalStack)", "item": [
   get_item("Evento del 202 argyle → COMPLETADO", "lastEventId", "Consulta DynamoDB en LocalStack hasta ver COMPLETADO."),
 ]},
 {"name": "04 · Rechazos (4xx)", "item": [
   webhook("401 · firma inválida", "argyle", 401, mode="bad-sig"),
   webhook("401 · sin firma", "argyle", 401, mode="no-sig"),
   webhook("400 · JSON inválido", "argyle", 400, body="{no es json"),
   webhook("400 · campo obligatorio ausente", "argyle", 400, body='{"eventId":"{{eventId}}","type":"x"}'),
   webhook("400 · X-Event-Id distinto del cuerpo", "argyle", 400, mode="id-mismatch"),
   webhook("404 · fuente desconocida", "otra-fuente", 404),
 ]},
 {"name": "05 · Idempotencia (duplicado)", "item": [
   webhook("Duplicado · 1er envío", "argyle", 202),
   webhook("Duplicado · 2º envío (mismo eventId)", "argyle", 202, mode="dup",
           desc="El MS acepta (202); la Lambda descarta el duplicado."),
   get_item("Duplicado → una sola fila COMPLETADO", "dupId", "El eventId duplicado termina COMPLETADO una vez."),
 ]},
 {"name": "06 · Métricas del MS", "item": [
   get("Métrica ingest_sqs_send_latency", "/actuator/prometheus",
       ["pm.test('Estado 200', () => pm.response.to.have.status(200));",
        "pm.test('Expone la métrica de latencia a SQS', () => pm.expect(pm.response.text()).to.include('ingest_sqs_send_latency'));"],
       desc="Corre después de los envíos para que la métrica ya exista.")
 ]},
 {"name": "99 · Manual (503)", "description": "Requiere `docker pause poc-asr1-localstack` antes de ejecutar y `docker unpause` después. Pon simulateSqsDown=true en el environment para activarla; si no, se omite.",
  "item": [ {
    "name": "503 · SQS no confirma",
    "event": [{"listen": "test", "script": {"type": "text/javascript", "exec": lines("""
const active = pm.environment.get('simulateSqsDown') === 'true';
const t = active ? pm.test : pm.test.skip;
t('Estado 503 con Retry-After', () => {
  pm.response.to.have.status(503);
  pm.expect(pm.response.headers.get('Retry-After')).to.eql('5');
});
""")}}],
    "request": {"method": "POST", "header": hdr(),
        "body": {"mode": "raw", "raw": VALID_BODY, "options": {"raw": {"language": "json"}}},
        "url": {"raw": "{{baseUrl}}/webhooks/argyle", "host": ["{{baseUrl}}"], "path": ["webhooks", "argyle"]}}
 }]},
]

collection = {
  "info": {"_postman_id": str(uuid.uuid4()), "name": "PoC ASR1 · MS de ingesta",
           "description": "Pruebas del MS de ingesta de webhooks (datos sintéticos, uso académico). La firma HMAC se calcula en el pre-request del colección. Requiere el entorno local en marcha (scripts/cluster-up.sh).",
           "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
  "event": [{"listen": "prerequest", "script": {"type": "text/javascript", "exec": PRE}}],
  "variable": [{"key": "baseUrl", "value": "http://localhost:8080"},
               {"key": "localstackUrl", "value": "http://localhost:4566"},
               {"key": "tableName", "value": "poc-asr1-idempotency"},
               {"key": "hmacSecret", "value": "poc-local-secret"}],
  "item": folders,
}
env = {"id": str(uuid.uuid4()), "name": "PoC ASR1 · local",
       "values": [{"key": "baseUrl", "value": "http://localhost:8080", "enabled": True},
                  {"key": "localstackUrl", "value": "http://localhost:4566", "enabled": True},
                  {"key": "tableName", "value": "poc-asr1-idempotency", "enabled": True},
                  {"key": "hmacSecret", "value": "poc-local-secret", "type": "secret", "enabled": True},
                  {"key": "simulateSqsDown", "value": "false", "enabled": True}],
       "_postman_variable_scope": "environment"}
json.dump(collection, open("postman/poc-asr1.postman_collection.json", "w"), ensure_ascii=False, indent=2)
json.dump(env, open("postman/local.postman_environment.json", "w"), ensure_ascii=False, indent=2)
print("ok")
