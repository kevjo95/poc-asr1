# P3 · Estrés con autoescalado en AWS (EKS)

Corrida `p3-20261124-005614` (informe: `results/summaries/p3-20261124-005614-informe.md`). Mismo entorno que `P2-aws.md`. Variante acortada: 5 escalones de 2 min
desde 800 hasta 1 200 req/s (`START_RATE=800 STEPS=5 STEP_S=120`), porque a 500 req/s el HPA no escala (P2).

## Resultado
| Escalón | p99 | Errores | Peticiones |
|---|---|---|---|
| 800/s | 29,8 ms | 0 % | 95 992 |
| 900/s | 35,4 ms | 0 % | 107 499 |
| 1 000/s | 51,9 ms | 0 % | 119 499 |
| 1 100/s | 25,9 ms | 0 % | 131 499 |
| 1 200/s | 26,3 ms | 0 % | 143 500 |

597 989 peticiones, todas `202`; `dropped_iterations` = 0; k6 con código de salida 0. **No se alcanzó el punto de quiebre** a 1 200 req/s con 8 réplicas.

## Escalado (criterio: réplicas nuevas atendiendo en ≤ 3 min, incluyendo nodo nuevo)
| t (s) | Evento |
|---|---|
| 61 | CPU 96 %: el HPA pide 5 réplicas |
| 125 | 5 réplicas listas, **64 s** después (la quinta requirió un nodo nuevo) |
| 198 | CPU 131 %: el HPA pide 8 réplicas |
| 205 | 6 réplicas listas (había hueco en el nodo creado antes) |
| 264 | 8 réplicas listas, **66 s** después de la decisión (requirió otro nodo nuevo) |

Pods nuevos, de creación a *Ready*: mín 9 s, promedio 51 s, **máx 67 s** (incluye aprovisionar el nodo, descargar la imagen y arrancar la JVM). **Cumple ≤ 3 min con holgura**; supera por 7 s el objetivo
interno de < 60 s por pod. CPU máxima del HPA 137 % del request; con 8 réplicas, 54–97 %. CPU máxima de un pod: 1 051 m.

## Conciliación
Nivel 1: 597 989 `202` = 597 989 mensajes en SQS (CloudWatch), diferencia 0. Nivel 2 parcial al terminar el script (la Lambda drena a ~200–300 msg/s): DLQ 0; el vaciado completo se verifica después por separado.
