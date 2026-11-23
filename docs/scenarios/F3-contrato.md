# F3 · Contrato del MS de ingesta

**Objetivo.** Verificar `POST /webhooks/{source}` contra la especificación (§6.1 de la PoC).

**Preparación.** Infra local aplicada (F1); imagen `poc-asr1/ingest-ms:0.1.0` corriendo en dos instancias:
una conectada a LocalStack (`:8080`) y otra con el endpoint de SQS inalcanzable (`:8081`, timeout 1 s) para forzar el 503.

**Comando.** `./scripts/f3-contrato.sh` (variables `BASE_URL`, `BAD_URL`).

| Caso | Esperado |
|---|---|
| Firma y cuerpo válidos (`argyle` y `central-payments`) | 202 |
| Firma inválida / sin firma | 401 (y no se persiste) |
| JSON inválido / campo obligatorio ausente / `X-Event-Id` distinto del cuerpo | 400 |
| Fuente desconocida | 404 |
| SQS no confirma (timeout) | 503 con `Retry-After` |

**Resultado (local).** 9 de 9 casos correctos: **OK**. Evidencia: `results/summaries/f3-contrato-local.txt`.
Además, 10 pruebas unitarias en `services/ingest-ms` (3 de firma, 7 de contrato) verifican que el MS nunca llama a
la cola con firma o cuerpo inválidos.

**Nota de diseño.** La firma se valida antes de interpretar el cuerpo; por eso una firma inválida prevalece (401) sobre un JSON inválido (400).
