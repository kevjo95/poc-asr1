# Informe P0 · p0-20261123-211514

- Peticiones: **42230** · `202`: **33342** · no-202: 8888
- Iteraciones descartadas por k6 (`dropped_iterations`): **4104** ⚠️ el generador (o el MS) no sostuvo la tasa pedida
- Código de salida de k6: 99 (99 = algún umbral no se cumplió)

## Latencia y errores por fase

| Fase | Tasa lograda | p95 (ms) | p99 (ms) | Errores | ¿Cumple p99<300 y err<0,1 %? |
|---|---|---|---|---|---|
| s0100 | 100/s (objetivo 100/s) | 3.0 | 3.9 | 0.000 % | sí |
| s0200 | 198/s (objetivo 200/s) | 2.4 | 1035.3 | 0.000 % | NO |
| s0300 | 298/s (objetivo 300/s) | 1.7 | 2.6 | 0.000 % | sí |
| s0400 | 398/s (objetivo 400/s) | 1.5 | 181.7 | 0.000 % | sí |
| s0500 | 399/s (objetivo 500/s) | 5001.0 | 5001.2 | 70.787 % | NO |
| s0600 | 14/s (objetivo 600/s) | 0.0 | 0.0 | 100.000 % | NO |
| s0700 | 0/s (objetivo 700/s) | 0.0 | 0.0 | 0.000 % | sí |

**Capacidad por réplica (1 réplica fija, HPA apagado): ≈ 400 req/s** (último escalón con p99 < 300 ms y errores < 0,1 %).
Valor objetivo de referencia con el margen del documento (×0,6): ≈ 240 req/s por réplica.
Réplicas para 500/s con esa capacidad: 1.2; con margen del 40 %: 2.1.
Primer escalón fuera de criterio: **s0200** (p99 1035 ms, errores 0.00 %).

## Réplicas y CPU

- Réplicas *ready*: inicio **1** → máximo **1** → final 1

Línea de tiempo (cada ~30 s): `t(s) ready/desired cpu%`

`1s:1/-/-%  31s:1/-/-%  62s:1/-/-%  92s:1/-/-%  123s:1/-/-%  153s:None/-/-%`

- CPU máxima observada en un pod: **306m** (request 100m, límite 2).

## Conciliación de pérdidas

```
Nivel 1 · 202 contados por k6 = 33342 · mensajes persistidos en SQS = 34629 · diferencia = -1287
Nivel 2 · muestra procesada por la Lambda en 5 s: COMPLETADO=60, EN_PROCESO=0, DLQ=0, pendientes en cola=34559
         (backlog parcial: LocalStack procesa ~9 msg/s; se espera EN_PROCESO=0 y DLQ=0)
```

> Entorno local con recursos reducidos en proporción (ADR 0006): p99 y tiempo de escalado son indicativos, no comparables con producción.
