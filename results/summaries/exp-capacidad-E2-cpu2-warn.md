# Informe P0 · p0-20261123-212018

- Peticiones: **40458** · `202`: **32065** · no-202: 8393
- Iteraciones descartadas por k6 (`dropped_iterations`): **3478** ⚠️ el generador (o el MS) no sostuvo la tasa pedida
- Código de salida de k6: 99 (99 = algún umbral no se cumplió)

## Latencia y errores por fase

| Fase | Tasa lograda | p95 (ms) | p99 (ms) | Errores | ¿Cumple p99<300 y err<0,1 %? |
|---|---|---|---|---|---|
| s0100 | 100/s (objetivo 100/s) | 3.1 | 4.0 | 0.000 % | sí |
| s0200 | 198/s (objetivo 200/s) | 2.3 | 228.3 | 0.000 % | sí |
| s0300 | 298/s (objetivo 300/s) | 1.7 | 2.3 | 0.000 % | sí |
| s0400 | 398/s (objetivo 400/s) | 1.5 | 240.7 | 0.000 % | sí |
| s0500 | 354/s (objetivo 500/s) | 5001.0 | 5001.2 | 79.101 % | NO |
| s0600 | 0/s (objetivo 600/s) | 0.0 | 0.0 | 100.000 % | NO |
| s0700 | 0/s (objetivo 700/s) | 0.0 | 0.0 | 0.000 % | sí |

**Capacidad por réplica (1 réplica fija, HPA apagado): ≈ 400 req/s** (último escalón con p99 < 300 ms y errores < 0,1 %).
Valor objetivo de referencia con el margen del documento (×0,6): ≈ 240 req/s por réplica.
Réplicas para 500/s con esa capacidad: 1.2; con margen del 40 %: 2.1.
Primer escalón fuera de criterio: **s0500** (p99 5001 ms, errores 79.10 %).

## Réplicas y CPU

- Réplicas *ready*: inicio **1** → máximo **1** → final 1

Línea de tiempo (cada ~30 s): `t(s) ready/desired cpu%`

`0s:1/-/-%  30s:1/-/-%  61s:1/-/-%  91s:1/-/-%  122s:1/-/-%  152s:None/-/-%`

- CPU máxima observada en un pod: **277m** (request 100m, límite 2).

## Conciliación de pérdidas

```
Nivel 1 · 202 contados por k6 = 32065 · mensajes persistidos en SQS = 34479 · diferencia = -2414
Nivel 2 · muestra procesada por la Lambda en 5 s: COMPLETADO=60, EN_PROCESO=0, DLQ=0, pendientes en cola=34409
         (backlog parcial: LocalStack procesa ~9 msg/s; se espera EN_PROCESO=0 y DLQ=0)
```

> Entorno local con recursos reducidos en proporción (ADR 0006): p99 y tiempo de escalado son indicativos, no comparables con producción.
