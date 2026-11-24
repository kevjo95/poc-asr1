# Qué debe modificarse en el documento de la clase (registro vivo)

Cada fila liga un hallazgo de la PoC con la sección del documento *G2 · The Money App Proyecto 2* que debe ajustarse. Se actualiza en cada prueba.
Estado: **Confirmado** (hay evidencia ejecutada) · **Propuesto** (decisión de redacción) · **Pendiente** (espera una prueba).

## A. Alcance y entorno (§7 y relacionados)
| # | Qué cambiar | Por qué / evidencia | Estado |
|---|---|---|---|
| A1 | §7 (intro): el entorno ya no es "AWS/ECS Fargate" sino **Kubernetes local (kind) + LocalStack**, con Terraform con dos destinos (LocalStack y AWS) | `docs/spike-01`, ADR 0002/0003; Fargate no replica el HPA observado en producción | Confirmado |
| A2 | §7.1 tabla: "Servicio AWS" → "Componente"; generador k6 en el equipo, no EC2; la "Función publicadora" pasa a **Lambda de conciliación** y va tras la cola | F1–F5 en `docs/scenarios/` | Confirmado |
| A3 | §7.3 costos: la ejecución local no tiene costo en la nube; el costo de una corrida en AWS queda por definir | ADR 0003 | Propuesto |
| A4 | Limitación 3: la Lambda y la idempotencia **sí participan**, en forma mínima | F2 (50 únicos + 10 duplicados → 50 `COMPLETADO`) | Confirmado |
| A5 | **Nueva limitación:** p99 y tiempo de escalado locales son *indicativos*, no comparables con producción (host, Docker Desktop, LocalStack comparten CPU; ver B3) | P0/P2 | Confirmado |
| A6 | **Nueva limitación:** producción usa HTTP Basic y la PoC firma con HMAC (`X-Signature`) | spike-01 §3 #7 | Confirmado |

## B. Métricas, recursos y escalado (§5, §7.2, §9)
| # | Qué cambiar | Por qué / evidencia | Estado |
|---|---|---|---|
| B1 | "125/s **sostenidos**" → "125/s **en promedio**" (900.000 webhooks en 2 h; la base de 1 M usuarios, independiente de los usuarios activos) | ADR 0005 | Propuesto |
| B2 | HPA: **mín 4 / máx 8, CPU 80 % del request**, ventana de subida 0 s y de bajada 300 s (no "2–10" ni `ALBRequestCountPerTarget`). §9: ejemplo "de 2 a 8 réplicas" → "de 4 a N" | HPA observado en producción (spike-01 §2.3) | Confirmado |
| B3 | El **request de CPU** condiciona cuándo escala el HPA: a 100m el HPA reaccionaba al tráfico base. Documentar el request/límite usado y justificarlo | P2 intento 1; ADR 0006 enmienda 2 | Confirmado |
| B4 | Capacidad por réplica (req/s con p99 < 300 ms): ~200/s con CPU 100m/500m en local. Repetir con el perfil 300m/1000m y citar el valor en §7.2 para justificar "4 réplicas cubren 500/s" | P0 intento 2 | Pendiente (repetir P0) |
| B5 | "Tiempo de escalado ≤ 3 min" debe medirse desde el inicio de la ráfaga hasta que la última réplica nueva está *Ready* y **separar tramos** (decisión del HPA, arranque del pod, nodo nuevo). Local: pods *Ready* en 9–11 s; el nodo nuevo no aplica en kind | P2 intento 1 y 2 | Parcial |
| B6 | Reconocer que el arranque en frío de la JVM (CPU > 150 %) puede disparar el HPA; la prueba exige **pre-calentamiento** y estabilidad previa | P2 intento 1 | Confirmado |

## C. Criterios y medición de "0 perdidos"
| # | Qué cambiar | Por qué / evidencia | Estado |
|---|---|---|---|
| C1 | Definir "0 perdidos" en **dos niveles**: (1) todo `202` está en SQS (`202` de k6 = mensajes enviados) y (2) lo procesado por la Lambda queda `COMPLETADO` sin DLQ ni `EN_PROCESO` atascados | P0/P2: sin pérdidas de lo confirmado | Confirmado |
| C2 | Aclarar que SQS puede contener **más** mensajes que `202` (el cliente expira antes de recibir la respuesta pero el MS ya persistió): el diseño necesita la idempotencia por `eventId` | P0: +4.151; P2-1: +791 | Confirmado |
| C3 | "Errores < 0,1 %" debe medirse **en el cliente** (k6) y no solo en el MS: el MS no ve los fallos de conexión previos a la aplicación | P2 intento 1: k6 0,89 % vs MS 0 % | Confirmado |

## D. Hallazgos de operación que enriquecen el documento (riesgos y recomendaciones)
| # | Hallazgo | Evidencia | Estado |
|---|---|---|---|
| D1 | La *liveness* con `timeout` de 1 s y poco umbral reinicia pods saturados y agrava la caída. Recomendar `timeoutSeconds: 3`, `failureThreshold: 6` | P0 intento 2 (reinicio por *liveness*) | Confirmado |
| D2 | Dimensionar memoria con holgura sobre el heap (heap 512 MiB + sobrecarga de JVM > 768 MiB → `OOMKilled`) | P0 intento 1 | Confirmado |
| D3 | El servicio degrada **de golpe**, no gradualmente (0 % → 9 % → 88 % de errores en dos escalones): conviene escalar antes de saturar | P0 intento 2 | Confirmado |
| D4 | El producto productivo nunca ha escalado en 67 días: la hipótesis solo se valida con carga sintética | spike-01 §2.3 | Confirmado |

## E. Pendiente de decidir con el grupo
- Mantener el documento 100 % local o dejar abierta una corrida en AWS (el repo ya tiene el Terraform del destino AWS, solo validado).
- Si el "tiempo de escalado" local debe presentarse como cumplimiento o solo como evidencia de la dinámica (la medición completa exige un nodo nuevo, que kind no tiene).
