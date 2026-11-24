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
| A4b | **Decisión (23-nov):** en las pruebas de carga locales la Lambda queda fuera de la medición (pausada); solo se valida su funcionamiento en F2/F4 y en la muestra de conciliación. El tráfico combinado MS + Lambda se deja para una corrida en AWS, donde la Lambda escala sin competir por CPU con SQS | LocalStack procesa ~9 msg/s y contamina la latencia del MS | Decidido |
| A5 | **Nueva limitación:** p99 y tiempo de escalado locales son *indicativos*, no comparables con producción (host, Docker Desktop, LocalStack comparten CPU; ver B3) | P0/P2 | Confirmado |
| A6 | **Nueva limitación:** producción usa HTTP Basic y la PoC firma con HMAC (`X-Signature`) | spike-01 §3 #7 | Confirmado |

## B. Métricas, recursos y escalado (§5, §7.2, §9)
| # | Qué cambiar | Por qué / evidencia | Estado |
|---|---|---|---|
| B1 | "125/s **sostenidos**" → "125/s **en promedio**" (900.000 webhooks en 2 h; la base de 1 M usuarios, independiente de los usuarios activos) | ADR 0005 | Propuesto |
| B2 | HPA: **mín 4 / máx 8, CPU 80 % del request**, ventana de subida 0 s y de bajada 300 s (no "2–10" ni `ALBRequestCountPerTarget`). §9: ejemplo "de 2 a 8 réplicas" → "de 4 a N" | HPA observado en producción (spike-01 §2.3) | Confirmado |
| B3 | El **request de CPU** fija el umbral del HPA (80 % del request) y debe justificarse. Medido con la JVM caliente: ~1m de CPU por req/s por pod; con request 100m el HPA reacciona a la ráfaga (~125 %) y no a la base (~31 %); con 300m no escaló en absoluto. Documentar request/límite usados y esta relación | P2 intentos 1 y 2; ADR 0006 enmiendas 2–3 | Confirmado |
| B4 | Capacidad por réplica (p99 < 300 ms), medida con el generador **dentro del clúster**: ~200–300 req/s con límite de CPU 1000m (la JVM ve 1 CPU) y ~400 req/s con 2000m (2 CPUs). Citar en §7.2 para justificar el dimensionamiento del mínimo de réplicas. Con Java 25 se repite (pendiente) | `results/summaries/exp-capacidad-*.md` | Parcial |
| B5 | "Tiempo de escalado ≤ 3 min": medir desde el inicio de la ráfaga hasta que la última réplica nueva está *Ready* y **separar tramos**. Local: el HPA llegó a 8 réplicas en **86 s** y los pods nuevos tardaron **5 s** en estar *Ready*; el tramo de nodo nuevo no se puede medir en kind (solo en AWS) | P2 intento 3; plan 0002 | Parcial (HPA y pod medidos; nodo pendiente) |
| B6 | Reconocer que el arranque en frío de la JVM (CPU > 150 %, ~3,6m por req/s frente a ~1m en caliente) puede disparar el HPA; la prueba exige **pre-calentamiento** y estabilidad previa. Esto también aplica a producción: un pod nuevo consume CPU extra al arrancar | P2 intentos 1 y 2 | Confirmado |

## C. Criterios y medición de "0 perdidos"
| # | Qué cambiar | Por qué / evidencia | Estado |
|---|---|---|---|
| C1 | Definir "0 perdidos" en **dos niveles**: (1) todo `202` está en SQS (`202` de k6 = mensajes enviados) y (2) lo procesado por la Lambda queda `COMPLETADO` sin DLQ ni `EN_PROCESO` atascados | P0/P2: sin pérdidas de lo confirmado | Confirmado |
| C2 | Aclarar que SQS puede contener **más** mensajes que `202` (el cliente expira antes de recibir la respuesta pero el MS ya persistió): el diseño necesita la idempotencia por `eventId` | P0: +4.151; P2-1: +791 | Confirmado |
| C3 | "Errores < 0,1 %" debe medirse **en el cliente** (k6) y no solo en el MS: el MS no ve los fallos de conexión previos a la aplicación | P2 intento 1: k6 0,89 % vs MS 0 % | Confirmado |
| C4 | La latencia que mide el generador de carga no es la del servicio: en dos corridas k6 midió p99 de 1,3–1,6 s mientras el MS registraba decenas de ms (4 y 8 réplicas). Medir el generador **dentro del clúster** o reportar ambas vistas | P2 intentos 1 y 2 | Confirmado; causa por aislar |

## D. Hallazgos de operación que enriquecen el documento (riesgos y recomendaciones)
| # | Hallazgo | Evidencia | Estado |
|---|---|---|---|
| D1 | La *liveness* con `timeout` de 1 s y poco umbral reinicia pods saturados y agrava la caída. Recomendar `timeoutSeconds: 3`, `failureThreshold: 6` | P0 intento 2 (reinicio por *liveness*) | Confirmado |
| D2 | Dimensionar memoria con holgura sobre el heap (heap 512 MiB + sobrecarga de JVM > 768 MiB → `OOMKilled`) | P0 intento 1 | Confirmado |
| D3 | El servicio degrada **de golpe**, no gradualmente (0 % → 9 % → 88 % de errores en dos escalones): conviene escalar antes de saturar | P0 intento 2 | Confirmado |
| D4 | El producto productivo nunca ha escalado en 67 días: la hipótesis solo se valida con carga sintética | spike-01 §2.3 | Confirmado |

## F. Aporte adicional: AS-IS → TO-BE de configuración
| # | Qué agregar | Evidencia | Estado |
|---|---|---|---|
| F1 | Sección con la tabla AS-IS (servicio de referencia) frente a TO-BE (MS de ingesta): CPU, hilos, log, memoria, *liveness*, HPA | `docs/as-is-to-be-configuracion.md` | En construcción |
| F2 | Aclarar que la configuración de producción es una **línea base observada**, no un requisito: el MS de ingesta tiene un patrón de ráfagas distinto | ADR 0006; conversación del grupo | Propuesto |

## G. Runtime, concurrencia y medición (hallazgos del 23-nov)
| # | Qué cambiar | Por qué / evidencia | Estado |
|---|---|---|---|
| G1 | **Runtime: Java 25** (no 21). En Java 21, los virtual threads se atascan (*pinning*, `reason:MONITOR`) dentro del cliente HTTP de Apache del SDK de AWS: al atrasarse SQS se agotan los hilos portadores, el pod deja de atender sus sondas y Kubernetes lo reinicia. Java 25 (JEP 491) elimina esa fijación y es el runtime del servicio de referencia | `-Djdk.tracePinnedThreads`; ADR 0008 | Confirmado el atasco en Java 21; mejora en Java 25 pendiente de la comparación |
| G2 | Aclarar que el servicio de referencia **no configura virtual threads** (valores por defecto de Spring, Tomcat con 200 hilos). La PoC los activó; su mantenimiento depende de la comparación | Revisión de la configuración de los dos servicios de referencia | Confirmado |
| G3 | El número de hilos **no limita** a 500 req/s: con SQS en ~5 ms la concurrencia es ≈ 3 peticiones simultáneas (ley de Little). Limita el CPU y, ante un SQS lento, el *pool* de conexiones | Análisis; la variante de 400 hilos no llegó a medirse | Análisis (por medir) |
| G4 | **Límite de CPU y CPUs que ve la JVM:** con límite ≤ 1000m la JVM ve 1 CPU (`system_cpu_count=1`) y el pool de hilos portadores es de 1. Con 2000m (como producción) la capacidad por réplica sube de ~200–300 a ~400 req/s | Experimento E0–E3 | Confirmado |
| G5 | El **log INFO por petición no es un factor** de capacidad: WARN no mejora frente a INFO | E0 vs E1, E3 vs E2 | Confirmado |
| G6 | El colapso de una réplica saturada es **brusco y no determinista** (una prueba de 40 s a 500/s pasó limpia; otras con la misma configuración colapsaron). Ante un SQS lento aparecen `ApiCallTimeoutException` a los 2 s y el MS responde 503 con `Retry-After`, **sin perder lo confirmado** | Pruebas de 500 req/s; F4 | Confirmado |
| G7 | Recomendación de diseño: **separar el puerto de administración** (sondas en otro puerto/pool) y limitar la concurrencia hacia SQS (*bulkhead*) para que un SQS lento no deje al pod sordo | Pod no contestó *liveness*/*readiness* durante el colapso | Hipótesis (por probar) |
| G8 | **Medición:** el generador dentro del clúster elimina el ruido del equipo anfitrión en las pruebas de una réplica (p99 ~300 ms a 500 req/s sobre un solo pod), pero en P2 completo k6 sigue viendo p99 de 1,8 s por las paradas del emulador de SQS (ver G10). Reportar siempre la vista del cliente **y** la del servicio | P2 intentos 1–3 | Confirmado |
| G10 | **El emulador de SQS limita la prueba local:** con ~243.000 mensajes acumulados, `SendMessage` sufre paradas de 1–2 s y el MS las refleja 1:1 en su p99 (p99 del MS = p99 de su llamada a SQS en los picos). Fuera de las paradas, el MS responde en ~5 ms con 0 % de errores. El criterio de p99/errores del ASR1 requiere SQS real o un emulador más rápido | P2 intento 3 | Confirmado |
| G11 | Con request de CPU de 100m, el tráfico base (125 req/s sobre 4 pods ≈ 62 % del request) roza el umbral del 80 % y el HPA sube a 6 réplicas antes de la ráfaga. Usar el request de producción (200m) para que la base quede ~30 % y la ráfaga cruce el umbral | P2 intento 3; ADR 0006 enmienda 5 | Confirmado; ajuste por validar |
| G9 | Un **arranque en frío** directo a 500 req/s colapsa; con 20 s de calentamiento a 100 req/s no. Mantener el pre-calentamiento como parte del protocolo de prueba | Diagnóstico a 500/s con y sin calentamiento | Parcial |
| G12 | **El MS necesita el módulo `sts` del SDK de AWS para usar el rol por pod (IRSA) en EKS.** Sin él, el SDK ignora el token de identidad y cae al rol del nodo: SQS responde AccessDenied y el MS devuelve 503. En LocalStack no se detecta (credenciales estáticas). Es un requisito del TO-BE para producción si se usa IRSA; el rol del nodo rechazó la operación, lo que confirma el mínimo privilegio | Primer despliegue en AWS (23/24-nov); corregido en la imagen 0.2.1 | Confirmado |
| G13 | Los nodos gestionados de EKS no heredan la etiqueta `project` de las etiquetas por defecto del proveedor (solo llevan `eks:cluster-name`). Cualquier verificación de residuos por etiqueta `project` da falsos negativos: listar todas las instancias | Verificación del `apply` | Confirmado |
| G14 | En EKS el plano de control solo llega a los nodos por puertos concretos (443, 10250 y webhooks). Leer las métricas del MS por el proxy del API server (`/pods/<pod>:8080/proxy`) exige una regla de entrada al puerto 8080 desde el grupo de seguridad del clúster; sin ella la lectura se cuelga. En un entorno real, las métricas se recolectan con un agente dentro del clúster (Prometheus/CloudWatch agent) y no por el API server | Dashboard en AWS (24-nov) | Confirmado, regla añadida |

## E. Pendiente de decidir con el grupo
- Mantener el documento 100 % local o incluir la corrida en AWS: **plan 0002 redactado** (`docs/plans/0002-validacion-en-aws.md`), pendiente de aprobación y de que exista la cuenta. Es la única forma de medir el nodo nuevo dentro de los 3 min y la Lambda con carga.
- Si el "tiempo de escalado" local debe presentarse como cumplimiento o solo como evidencia de la dinámica (la medición completa exige un nodo nuevo, que kind no tiene).
