# P0 · Calibración (1 réplica fija)

**Objetivo.** Medir la capacidad por réplica con el HPA apagado: escalones de +50/s cada 60 s hasta que el p99 supere 300 ms
o los errores superen 0,1 %. El resultado fija el valor objetivo del escalado y el cálculo de réplicas para el pico.

**Comando.** `STEPS=12 STEP=50 START_RATE=50 STEP_S=60 ./scripts/run-scenario.sh p0`

## Intento 1 (`p0-20261123-193100`) · DESCARTADO
Resultado aparente: pasa hasta 200/s, falla en 250 y 300/s, "pasa" en 350/s y colapsa en 400/s (73 % de errores por timeout de 5 s).

**Diagnóstico.** El pod terminó con **OOMKilled** (código 137): con heap de 512 MiB y un límite de 768 MiB, la sobrecarga de la JVM
agotó la memoria, mientras su CPU nunca pasó de 162m de 500m. Además la sonda de *liveness* con timeout de 1 s lo reinició bajo carga.
Por eso la curva no es monótona y el "capacidad ≈ 350/s" que calculó el análisis **no es válido**.

**Hallazgos útiles.**
- El perfil reducido proporcional (ADR 0006) dejaba menos holgura de memoria que producción: la sobrecarga de la JVM no escala de forma proporcional.
- Conciliación: 95.491 mensajes en SQS frente a 89.938 `202` (diferencia −5.553). Hay **más** mensajes que confirmaciones porque el cliente
  expiró (5 s) en peticiones que el MS sí alcanzó a persistir: no hay pérdidas de lo confirmado, pero sí posibles reintentos, que la
  idempotencia absorbe.

**Correcciones aplicadas.** Memoria 1 GiB (heap 512 MiB) y `timeoutSeconds: 3` en las sondas (ADR 0006, enmienda).

## Intento 2 (`p0-20261123-195103`) · VÁLIDO
Perfil corregido (1 GiB, sondas con timeout 3 s). 1 réplica fija, escalones de 50/s cada 60 s. Evidencia: `results/summaries/p0-20261123-195103-informe.md`.

| Escalón | p99 | Errores |
|---|---|---|
| 50/s | 29 ms | 0 % |
| 100/s | 135 ms | 0 % |
| 150/s | 152 ms | 0 % |
| 200/s | 81 ms | 0 % |
| 250/s | 5000 ms (timeouts) | 9,4 % |
| 300/s | 5002 ms | 88 % → k6 aborta la prueba (regla de seguridad) |

**Resultado: capacidad de una réplica local ≈ 200 req/s** con p99 < 300 ms y 0 % de errores. Con 4 réplicas mínimas serían ≈ 800/s teóricos,
por encima de los 500/s del ASR1 (la P2 lo confirma o refuta con el HPA real).

**Cómo falla (hallazgo).** No degrada de forma gradual sino en cliff: sin OOM esta vez, pero el pod se **reinició por *liveness*** (código 143) al saturarse
(CPU medio 287m con límite 500m: el *throttling* de CPU frena el hilo que atiende las sondas). El reinicio deja al MS sin servicio unos
segundos y agrava la caída. En producción esto sugiere que la *liveness* no debe depender de la carga (mayor `failureThreshold`/`timeoutSeconds`),
y que conviene escalar antes de saturar (el HPA al 80 % del request dispara mucho antes del cliff).

**Conciliación.** Ver el informe. Hay más mensajes en SQS que `202` cuando el cliente expira antes de recibir la respuesta; la idempotencia absorbe los reintentos.

**Límites de la medición.** k6, el clúster y LocalStack comparten el mismo equipo: el p99 en 100–150/s (≈135–150 ms) es ruido de CPU compartida, no del MS.
