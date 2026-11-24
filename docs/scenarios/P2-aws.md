# P2 · Ráfaga del ASR1 en AWS (EKS)

Corrida `p2-20261124-002516` (informe: `results/summaries/p2-20261124-002516-informe.md`). Entorno: EKS 1.36, 2 nodos `m7i-flex.large` para el MS y 1 nodo
aparte para k6 (con *taint*), perfil de producción del MS (request 200m, límite 2000m, 3096 MiB, Java 25, hilos de plataforma, HPA 4–8 al 80 %), SQS, Lambda y DynamoDB reales,
entrada por NLB interno. Generador k6 dentro del clúster.

## Resultado
| Fase | Tasa | p99 | Errores |
|---|---|---|---|
| Calentamiento | 125/s | 29,7 ms | 0,232 % (87 timeouts del NLB, ver incidente) |
| Ráfaga 125→500 en 1 min | | 25,6 ms | 0 % |
| Sostenido | 500/s × 5 min | **24,6 ms** | 0 % |
| Regreso | 125/s | 24,2 ms | 0 % |

| Criterio ASR1 | Resultado |
|---|---|
| p99 < 300 ms a 500 req/s | **Cumple** (24,6 ms) |
| Errores < 0,1 % incluyendo el escalado | **Cumple** (0,042 % global; 0 % en ráfaga y sostenido) |
| 0 webhooks perdidos | **Cumple**: 243 662 `202` = 243 662 mensajes en SQS (CloudWatch) = 243 662 `COMPLETADO`; DLQ 0, `EN_PROCESO` 0 |
| Réplicas nuevas atendiendo en ≤ 3 min | **No medido**: el HPA nunca escaló (CPU máx. 75 % con 4 réplicas) |

## Lectura
Con SQS real y el generador aislado, 4 réplicas con el perfil de producción absorben 500 req/s con ~50 % de CPU (≈ 1 m de CPU por req/s). La ráfaga del ASR1 se cumple **sin escalar**:
el mínimo de 4 réplicas ya sobra. Esto contradice la lectura de las pruebas locales (donde LocalStack y la CPU compartida distorsionaban latencia y errores) y obliga a replantear
qué carga hace falta para ejercitar el autoescalado (P3 u otra variante).

## Incidentes durante la corrida (corregidos)
1. **MS sin el módulo `sts` del SDK** → sin IRSA, 503 (hallazgo G12; imagen 0.2.1).
2. **Lectura de métricas por el proxy del API server bloqueada** por el grupo de seguridad de los nodos (G14).
3. **NLB con IP de cliente preservada**: un cliente dentro del clúster cuyo nodo es destino del NLB pierde ~1/3 de las conexiones nuevas (G15). 87 timeouts en los primeros 40 s del calentamiento, antes de la corrección.
4. **Conteo de DynamoDB paginado**: el CLI en modo texto imprime una cifra por página; el nivel 2 de la conciliación se calculó a mano con el mismo dato (243 662) y `lib.sh` quedó corregido.
