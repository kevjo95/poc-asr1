# Colección de Postman

Pruebas del MS de ingesta con datos sintéticos. La firma HMAC se calcula sola en el pre-request de la colección.

| Archivo | Uso |
|---|---|
| `poc-asr1.postman_collection.json` | Colección (formato v2.1). Importar en Postman |
| `local.postman_environment.json` | Entorno `PoC ASR1 · local` (URLs y secreto HMAC sintético) |
| `generate.py` | Genera ambos archivos (fuente de verdad; ejecutar con `python3 postman/generate.py` desde la raíz) |

## Cómo usarla
1. Levantar el entorno: `./scripts/cluster-up.sh`
2. Postman → **Import** → seleccionar ambos JSON → elegir el entorno `PoC ASR1 · local`.
3. Ejecutar la colección completa (**Run collection**) o carpeta por carpeta.

## Contenido y resultado esperado
| Carpeta | Qué prueba | Esperado |
|---|---|---|
| 01 Salud y métricas | readiness y liveness | 200 `UP` |
| 02 Caminos felices | `argyle` y `central-payments` | 202 |
| 03 Verificación | consulta DynamoDB (LocalStack) hasta ver el evento | `COMPLETADO` |
| 04 Rechazos | firma inválida/ausente, JSON inválido, campo ausente, id distinto, fuente desconocida | 401 / 400 / 404 |
| 05 Idempotencia | mismo `eventId` dos veces | 202 + una sola fila `COMPLETADO` |
| 06 Métricas | `ingest_sqs_send_latency` | presente |
| 99 Manual (503) | SQS caído | 503 con `Retry-After` (solo si `simulateSqsDown=true`) |

**Prueba del 503:** `docker pause poc-asr1-localstack`, poner `simulateSqsDown = true` en el entorno y ejecutar la carpeta 99;
después `docker unpause poc-asr1-localstack` y volver a `false`.

Resultado de referencia (newman, 18 peticiones): **22 aserciones, 0 fallos**; la del 503 se omite por defecto.
Los modos de prueba se controlan con el header marcador `X-Test-Mode` (`bad-sig`, `no-sig`, `dup`, `id-mismatch`), que el
pre-request retira antes de enviar.
