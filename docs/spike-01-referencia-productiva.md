# Spike 01 · Línea base observada de un servicio de ingesta comparable

> Estado: **borrador para revisión** · Autores: grupo 2 + asistente de código
> Propósito: contrastar el documento de la PoC (`PoC-ingesta-webhooks.md`) y el ASR1 con lo observado
> en un servicio productivo comparable, y decidir qué se actualiza en el documento y qué se mantiene.
>
> **Uso académico.** Los valores aquí son supuestos de trabajo derivados de observación. El servicio
> de referencia se llama genéricamente "servicio de referencia (SR)". No se incluyen nombres, cuentas,
> identificadores ni código de la organización.

---

## 1. Qué se investigó y cómo

| Fuente | Acceso | Qué aportó |
|---|---|---|
| Código de dos servicios de webhooks (uno antiguo, uno más nuevo) | Lectura local | Lógica del flujo, seguridad, Helm |
| Consola de administración del clúster productivo | Lectura manual (capturas) | Deployment, recursos del pod, HPA |
| APIs de AWS en cuentas de pruebas y productiva | Solo lectura, rol limitado | Qué recursos existen; atributos de SQS denegados |
| Diagrama TO-BE de la entrega | Documento | Alcance: MS ingesta → SQS → Lambda → idempotencia |

**Limitaciones:** el endpoint del clúster es privado (no alcanzable desde el equipo local); el rol de
lectura en producción no puede leer atributos de SQS ni listar clústeres; no se vio el autoscaler de
nodos ni la capacidad libre de los nodos.

## 2. Hallazgos

### 2.1 Lógica del servicio (AS-IS)

- Patrón *delegate → coordinator → cliente downstream*. Cada webhook se procesa **dentro de la petición HTTP**
  y llama a otros servicios de forma síncrona.
- Responde **siempre 200**, incluso si el downstream falla: el evento se pierde. Es exactamente el
  problema que el TO-BE (persistir en cola y confirmar) busca resolver.
- El proveedor se autentica con **HTTP Basic** sobre una cadena de seguridad limitada a la ruta de webhooks.
- Los componentes TO-BE (Lambda publicadora, tabla de idempotencia, cola de ingesta) **no existen** aún
  en producción: son diseño.

### 2.2 Despliegue y recursos del pod (SR)

| Parámetro | Valor observado |
|---|---|
| CPU request / limit | 200m / 2000m |
| Memoria request / limit | 3096 MiB / 3096 MiB (garantizada) |
| JVM | G1, heap fijo de 2 GiB |
| Contenedores por pod | 2 en ejecución: aplicación + sidecar de malla (más un init) |
| Distribución | 4 réplicas en 4 nodos distintos (una por nodo) |
| Entrada | Balanceador de red interno → ingress de la malla de servicios |

### 2.3 Escalado horizontal (HPA del SR)

| Parámetro | Valor observado |
|---|---|
| Réplicas mín / máx | **4 / 8** |
| Métrica | CPU, **80 % del request** (≈ 160m por pod) |
| Uso actual | ~1 % (≈ 5m por pod): el mínimo es un piso de disponibilidad, no de demanda |
| Último escalado | Hace ~67 días (el HPA nunca ha tenido que actuar) |
| Escalar hacia arriba | Estabilización **0 s**; hasta **4 pods por 90 s** |
| Escalar hacia abajo | Estabilización **300 s**; hasta 4 pods por 90 s |
| Condición activa | `ScalingLimited: TooFewReplicas` (querría menos de 4) |

## 3. Diferencias frente al documento de la PoC

| # | Tema | Documento de la PoC | Observado en el SR | Coherente con la hipótesis | Propuesta |
|---|---|---|---|---|---|
| 1 | Cómputo | ECS Fargate | Kubernetes + HPA | Sí: el propio documento declara EKS como producción | **Cambiar el entorno de la PoC a Kubernetes** (kind) para validar el HPA real |
| 2 | Balanceo | ALB público | NLB interno + ingress de malla | Sí | Local: ingress equivalente; documentar la diferencia |
| 3 | Métrica de escalado | `ALBRequestCountPerTarget` | CPU al 80 % del request | Parcial | **Usar CPU 80 %** (lo que existe) y reportar la capacidad en req/s por pod desde P0 |
| 4 | Réplicas | mín 2, máx 10 | mín 4, máx 8 | Sí, con matiz | Probar 4/8. Si 8 pods no sostienen 500/s, **esa es la conclusión** (recomendar subir el máximo) |
| 5 | Tamaño del pod | 0,5 vCPU / 1 GB | 0,2–2 vCPU / 3 GiB | Sí | Usar el perfil del SR (reducido en local, ver §4) |
| 6 | Tiempo de escalado ≤ 3 min | Se mide hasta pod *healthy* | Suma HPA + arranque JVM + (posible) nodo nuevo | Sí | Medir cada tramo por separado |
| 7 | Firma del webhook | HMAC `X-Signature` | HTTP Basic | Sí (la PoC es más estricta) | Mantener HMAC; documentar que producción usa Basic |
| 8 | Alcance de la cola | Solo `SendMessage` | MS → SQS → Lambda → idempotencia | **Amplía el alcance** | Incluir Lambda + tabla de idempotencia en la PoC; el documento debe reflejarlo |
| 9 | Medida "0 perdidos" | `202` k6 vs `NumberOfMessagesSent` | Igual, más "procesados por la Lambda" | Sí | Agregar conciliación en dos niveles (enviados y procesados) |
| 10 | Runtime | Java 21 | Java 25 en el SR | Sí | ~~Mantener Java 21~~ **Corregido tras medir:** usar Java 25 como el SR (ver ADR 0008) |
| 11 | Generador de carga | EC2 con k6 | — | Sí | Local: k6 en el equipo, acotado por recursos |

## 4. Entorno local y límites

- Docker Desktop: 14 CPU, **3,8 GiB** de memoria (insuficiente para un pod del SR). Requiere ajuste a ≥ 16 GiB.
- Perfil reducido propuesto (misma *forma* de escalado, recursos proporcionales): request 100m, limit 500m,
  memoria 768 MiB, heap 512 MiB; HPA idéntico (4/8, CPU 80 %, ventanas 0 s y 300 s).
- **Lo que sí valida el entorno local:** el comportamiento del contrato (`202/400/401/503`), la
  idempotencia, la conciliación de pérdidas y la *dinámica* del HPA.
- **Lo que no valida:** latencia absoluta, p99 real a 500/s, tiempo de aprovisionamiento de nodos, cuotas de SQS.
  Un p99 local no sustituye la medición en AWS y se reportará como prueba funcional.

## 5. Riesgos y preguntas abiertas

1. ¿Existe autoscaler de nodos y hay capacidad libre para 4 pods más de 3 GiB? (Define el tiempo de escalado.)
2. ¿Cuál es la capacidad real por pod en req/s con p99 < 300 ms? (Se mide en P0.)
3. Configuración de la cola de ingesta (visibility timeout, redrive, DLQ): sin acceso de lectura; se fijará
   como supuesto propio en un ADR.
4. ¿La PoC se ejecutará solo en local o también contra la nube para la evidencia final?

## 6. Decisiones pendientes (a cerrar tras revisar el documento de la entrega)

| Decisión | Opciones | Recomendación inicial |
|---|---|---|
| Entorno de la PoC | Mantener ECS Fargate del documento / pasar a Kubernetes | Kubernetes, por coherencia con producción |
| Métrica del HPA | `ALBRequestCountPerTarget` / CPU 80 % | CPU 80 % |
| Rango de réplicas | 2–10 / 4–8 | 4–8 |
| Alcance | Solo ingesta → cola / ingesta → cola → Lambda → idempotencia | Incluir Lambda e idempotencia |

## 7. Próximos pasos

1. Revisar el documento de la entrega frente a la sección 3 y decidir qué se actualiza.
2. Registrar las decisiones en `docs/adr/`.
3. Construir `infra/` (kind + LocalStack + Terraform), `services/` y `deploy/helm/`.
