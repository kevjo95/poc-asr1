# Pruebas manuales del servicio

Entorno local: LocalStack (SQS, DynamoDB, Lambda) + clúster `kind` con el MS detrás de un HPA.
Todo usa datos sintéticos y el secreto HMAC local `poc-local-secret`.

## 0. Preparación
```bash
# Docker Desktop con >= 16 GiB (Settings > Resources)
./scripts/cluster-up.sh                       # levanta todo; deja el MS en http://localhost:8080
export KUBECONFIG=$HOME/.kube/poc-asr1.yaml   # solo para esta terminal (no toca tu ~/.kube/config)
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
AWS="aws --endpoint-url http://localhost:4566"
```
Salud: `curl localhost:8080/actuator/health` debe responder `{"status":"UP",...}`.

## 1. Enviar un webhook válido (debe dar 202)
```bash
ID="manual-$(date +%s)"
BODY='{"eventId":"'$ID'","type":"deposit.settled","occurredAt":"2026-12-01T13:00:00Z","accountId":"acc_1","amount":{"value":1250.75,"currency":"USD"}}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac poc-local-secret -hex | awk '{print $NF}')
curl -i -X POST localhost:8080/webhooks/argyle \
  -H 'Content-Type: application/json' -H "X-Event-Id: $ID" -H "X-Signature: sha256=$SIG" \
  --data-binary "$BODY"
```
Esperado: `HTTP/1.1 202` y `{"eventId":"manual-..."}`. Valores válidos de `source`: `argyle`, `central-payments`.

## 2. Ver que se procesó (idempotencia)
```bash
sleep 4
$AWS dynamodb get-item --table-name poc-asr1-idempotency --key '{"eventId":{"S":"'$ID'"}}' \
  --query 'Item.{id:eventId.S,estado:status.S}'
```
Esperado: `estado: COMPLETADO`. Repite el `curl` del paso 1 con el **mismo** `$ID`: sigue habiendo una sola fila.

## 3. Casos negativos
| Qué probar | Cómo | Esperado |
|---|---|---|
| Firma inválida | cambia `sha256=$SIG` por `sha256=deadbeef` | 401 |
| Sin firma | quita el header `X-Signature` | 401 |
| JSON inválido | `BODY='{no es json'` (firmado) | 400 |
| Campo ausente | `BODY='{"eventId":"x","type":"y"}'` (firmado) | 400 |
| `X-Event-Id` distinto | header con otro id | 400 |
| Fuente desconocida | `/webhooks/otra` | 404 |

## 4. Forzar un 503 (SQS no responde) y verificar la recuperación
```bash
docker pause poc-asr1-localstack      # SQS deja de responder
# repite el curl del paso 1: debe responder 503 con Retry-After: 5 en ~2 s (timeout explícito)
docker unpause poc-asr1-localstack
# repite el MISMO curl: ahora 202 y el evento termina COMPLETADO
```

## 5. Observar el HPA
```bash
kubectl get hpa ingest-ms -w          # objetivo 80 % de CPU, 4 a 8 réplicas
kubectl get pods -o wide              # reparto entre nodos
kubectl top pods                      # CPU y memoria por pod
```
Para generar carga rápida sin k6: `N=3000 PAR=50 ./scripts/f4-cero-perdidos.sh`.
La CPU en reposo ronda el 5-7 %; con carga sostenida debe subir hacia el 80 % y el HPA añade réplicas.

## 6. Métricas y logs
```bash
curl -s localhost:8080/actuator/prometheus | grep ingest_sqs_send_latency | head
kubectl logs deploy/ingest-ms --tail=20          # logs JSON con eventId y latencia del SendMessage
docker logs poc-asr1-localstack --tail 30        # ejecución de la Lambda
```
El NodePort reparte entre réplicas, así que cada `curl` a `/actuator` puede caer en un pod distinto.

## 7. Ver la cola y la DLQ
```bash
$AWS sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/poc-asr1-ingest \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
$AWS sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/poc-asr1-ingest-dlq \
  --attribute-names ApproximateNumberOfMessages
```
La cola debe quedar en 0 y la DLQ vacía.

## 8. Escenarios automáticos
`./scripts/f2-idempotencia.sh` · `./scripts/f3-contrato.sh` (requiere `BAD_URL`, ver su ficha) · `./scripts/f4-cero-perdidos.sh`

## 9. Limpieza
`./scripts/cluster-down.sh`
