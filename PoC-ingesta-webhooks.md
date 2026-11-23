# PoC · Escalabilidad del MS de ingesta de webhooks (The Money App)

> Documento semilla del repositorio de la PoC. Define qué se prueba, con qué, cómo se mide y qué evidencia se entrega.
> Fuente: sección 7 y ASR1 (5.1) de la Entrega 2 · Grupo 2 · ARTI4207 Architecting for the Cloud (MATI, Uniandes).

---

## 1. Contexto

The Money App recibe webhooks de su sponsor bank (Central Payments) y de su proveedor de nómina (Argyle). En el AS-IS, el MS de ingesta procesa cada webhook dentro del ciclo HTTP y llama de forma síncrona a sus consumidores. Si una llamada falla, el evento se pierde. En el TO-BE, el MS de ingesta solo valida, persiste en una cola y confirma. El resto del trabajo ocurre de forma asíncrona detrás de un backbone de eventos.

La PoC no prueba el backbone completo. Prueba **el punto de entrada**: si el MS de ingesta no escala ante la ráfaga de nómina, nada de lo que hay detrás importa.

## 2. Hipótesis

> Si el MS de ingesta no guarda estado y solo persiste en la cola antes de confirmar, puede escalar horizontalmente al ritmo del pico de nómina sin degradar la latencia ni generar errores.

## 3. ASR1 que se valida

| Elemento | Valor |
|---|---|
| Fuente | Sponsor bank (Central Payments) y proveedor de nómina (Argyle) |
| Estímulo | 900.000 webhooks en 2 h (125/s sostenidos); ráfaga de 125 → 500/s en 1 min, sostenida 5 min |
| Artefacto | MS de ingesta de webhooks y su escritura en la cola |
| Entorno | Día de nómina a 1M de usuarios; réplicas de día normal al inicio de la ráfaga |
| Respuesta | Escala horizontalmente, persiste cada webhook y confirma solo después de persistir |
| Medida | p99 < 300 ms a 500/s · errores < 0,1 % (incluido el escalado) · réplicas nuevas atendiendo en ≤ 3 min · 0 webhooks perdidos |

## 4. Alcance

**Dentro:** petición HTTP → ALB → MS de ingesta (ECS Fargate, autoscaling) → `SendMessage` a SQS → respuesta al cliente.

**Fuera (y por qué):** API Gateway, WAF, publicadora, idempotencia, bus y consumidores. Están sustentados en el diseño de la sección 1.1, no los mide el ASR1 y encarecen la prueba sin cambiar la respuesta a la hipótesis.

**Diferencias conscientes con producción:**

| Producción | PoC | Impacto en la validez |
|---|---|---|
| EKS + Istio, HPA | ECS Fargate, Service Auto Scaling | Se valida el MS y su escalado horizontal, no el mesh ni el clúster |
| NLB interno detrás de API Gateway | ALB público restringido por SG a la IP del generador | El ALB entrega la métrica de requests por réplica que necesita el autoscaling |
| Subredes privadas + endpoints | Tareas en subred pública con IP pública, SG que solo acepta tráfico del ALB | Evita NAT Gateway (~USD 1/día). No es un patrón de producción |

---

## 5. Arquitectura de la PoC

```
 ┌──────────────┐   HTTPS/HTTP    ┌─────┐        ┌──────────────────────────┐   SendMessage   ┌──────────────┐
 │ k6 en EC2    │ ──────────────► │ ALB │ ─────► │ ECS Fargate · MS ingesta │ ──────────────► │ SQS ingesta  │
 │ c5.xlarge    │                 └─────┘        │ N réplicas (2 → 10)      │                 │ (+ DLQ)      │
 └──────────────┘                                └──────────────────────────┘                 └──────────────┘
        │                                                     ▲
        │                                    ECS Service Auto Scaling (target tracking)
        ▼
  results/*.json            CloudWatch: ALB, ECS, SQS · Budget alarm · Terraform destroy
```

| Bloque | Servicio | Configuración inicial |
|---|---|---|
| Generador de carga | k6 en EC2 `c5.xlarge`, misma región | Executor `ramping-arrival-rate`; `preAllocatedVUs` holgados |
| Balanceador | Application Load Balancer | Health check `/actuator/health`, deregistration delay 30 s |
| MS de ingesta | Spring Boot en ECS Fargate | 0,5 vCPU / 1 GB por tarea; min 2, max 10 |
| Escalado | Target tracking sobre `ALBRequestCountPerTarget` | Valor objetivo calibrado en P0 (ver §8) |
| Cola | SQS estándar + DLQ | Retención 1 día; se purga al terminar |
| IaC | Terraform | `apply` y `destroy` repetibles; todo etiquetado `project=poc-ingesta` |
| Región | `us-east-1` | Misma región que el blueprint AWS |

---

## 6. Especificación del MS de ingesta

**Stack:** Java 21, Spring Boot 3.x, AWS SDK v2 (cliente SQS), Actuator + Micrometer.

### 6.1 Contrato

`POST /webhooks/{source}`, donde `source ∈ {central-payments, argyle}`

Headers:
- `Content-Type: application/json`
- `X-Signature: sha256=<hex>`: HMAC-SHA256 del body con un secreto compartido.
- `X-Event-Id: <uuid>`: id del evento del proveedor.

Body sintético (1–2 KB, igual que el volumen real):

```json
{
  "eventId": "6f1c…",
  "type": "deposit.settled",
  "occurredAt": "2026-12-01T13:00:00Z",
  "accountId": "acc_…",
  "amount": { "value": 1250.75, "currency": "USD" },
  "metadata": { "employer": "…", "payPeriod": "2026-11-16/2026-11-30" }
}
```

| Respuesta | Cuándo |
|---|---|
| `202 Accepted` | Solo después de que SQS confirmó el `SendMessage` |
| `400` | JSON inválido o campos obligatorios ausentes |
| `401` | Firma inválida |
| `503` | SQS no confirmó (timeout o error). El proveedor reintenta |

### 6.2 Reglas de diseño (no negociables para que la prueba sea válida)

1. **Confirmar después de persistir.** El `202` se envía únicamente cuando SQS responde OK. Nunca se encola en memoria, porque eso invalidaría la medida de "0 perdidos".
2. **Sin estado.** No hay caché local, sesión ni archivo. Cualquier réplica atiende cualquier petición.
3. **Un `SendMessage` por webhook.** No se agrupa en lotes: un lote retrasa el ACK y cambia la semántica de la prueba.
4. **Atributos del mensaje:** `eventId`, `source`, `type` y `receivedAt`, para conciliar después.
5. **Concurrencia:** virtual threads (`spring.threads.virtual.enabled=true`) y un cliente HTTP del SDK con pool dimensionado (p. ej. `maxConcurrency=200`). Hay que documentar el valor usado.
6. **Timeouts explícitos hacia SQS** (p. ej. 2 s) para que un SQS lento se convierta en `503` medible y no en un hilo colgado.
7. **Observabilidad:** logs JSON con `eventId` y latencia del `SendMessage`; métrica Micrometer `ingest.sqs.send.latency`.
8. **Secreto HMAC** por variable de entorno, inyectada desde SSM Parameter Store en la task definition. Nunca en el repositorio.

### 6.3 Arranque

Hay que medir y reportar el tiempo desde que la tarea entra en `RUNNING` hasta que el health check del ALB pasa, porque es el componente dominante del "≤ 3 min". Si supera los 60 s, evaluar Class Data Sharing (CDS) o reducir dependencias antes de tocar el autoscaling.

---

## 7. Infraestructura (Terraform)

Módulos sugeridos:

| Módulo | Recursos |
|---|---|
| `network` | VPC, 2 subredes públicas en 2 AZ, IGW, SG del ALB (solo IP del generador), SG de tareas (solo desde el ALB) |
| `ecr` | Repositorio de la imagen |
| `queue` | SQS ingesta + DLQ (redrive) |
| `service` | Cluster ECS, task definition, rol de tarea con `sqs:SendMessage` **solo** sobre la cola, servicio ECS, target group |
| `alb` | ALB, listener, target group, health check |
| `autoscaling` | `aws_appautoscaling_target` (min 2, max 10) y política de target tracking |
| `loadgen` | EC2 `c5.xlarge` con k6 instalado por user-data; acceso por SSM Session Manager (sin SSH abierto) |
| `observability` | Dashboard de CloudWatch con las métricas de §9 |
| `guardrails` | AWS Budget con alarma a USD 10; tags de costo |

Variables clave: `region`, `task_cpu`, `task_memory`, `min_tasks`, `max_tasks`, `target_requests_per_task`, `loadgen_cidr`.

> Antes de ejecutar: revisar las cuotas de la cuenta (tareas Fargate concurrentes por región). La prueba debe medir el diseño, no un límite de la cuenta.

---

## 8. Escenarios

Orden de ejecución recomendado. P0 no aparece en el documento: es la calibración que permite fijar el autoscaling con un dato y no con una suposición.

| # | Escenario | Estímulo | Autoscaling | Qué produce |
|---|---|---|---|---|
| P0 | Calibración | Rampa desde 50/s con **1 réplica fija** hasta que el p99 supere 300 ms | Apagado | Capacidad por réplica → valor objetivo del target tracking |
| P1 | Base | 125/s durante 30 min, desde el mínimo de réplicas | Encendido | Línea base de latencia y réplicas para la tasa sostenida |
| P2 | Ráfaga (ASR1) | 125 → 500/s en 1 min, sostenido 5 min | Encendido | Tiempo de escalado, errores durante el escalado, p99 a 500/s |
| P3 | Estrés | Rampa desde 500/s hasta p99 > 300 ms o errores > 0,1 % | Encendido (max 10) | Punto de quiebre del sistema con el máximo de réplicas |

**Cálculo del objetivo de target tracking** (`ALBRequestCountPerTarget` se mide en requests por minuto):

```
objetivo = capacidad_por_réplica (req/s, de P0) × 60 × 0,6
```

El 0,6 deja un 40 % de margen para absorber la ráfaga mientras llegan las réplicas nuevas.

**Esqueleto de k6 para P2** (en `load/p2-rafaga.js`):

```js
export const options = {
  scenarios: {
    p2: {
      executor: 'ramping-arrival-rate',
      startRate: 125, timeUnit: '1s',
      preAllocatedVUs: 300, maxVUs: 1500,
      stages: [
        { target: 125, duration: '5m' },  // calentamiento a tasa base
        { target: 500, duration: '1m' },  // ráfaga
        { target: 500, duration: '5m' },  // sostenido
        { target: 125, duration: '2m' },  // regreso
      ],
    },
  },
  thresholds: {
    'http_req_duration{expected_response:true}': ['p(99)<300'],
    'http_req_failed': ['rate<0.001'],
  },
};
```

Cada petición genera un `eventId` único, firma el body con `k6/crypto` (HMAC-SHA256) y se etiqueta con el escenario. Exportar con `--summary-export results/p2-summary.json` y `--out json=results/p2-raw.json`.

---

## 9. Medición y criterio de aceptación

| Medida | Fuente | Aceptación |
|---|---|---|
| p99 de respuesta a 500/s | k6 (P2, ventana sostenida) | < 300 ms |
| Errores | k6: no-2xx + timeouts (P1 y P2) | < 0,1 % |
| Tiempo de escalado | Desde el inicio de la ráfaga hasta que la última réplica nueva está *healthy* en el target group (eventos de ECS + `HealthyHostCount` del ALB) | ≤ 3 min |
| Eventos perdidos | `202` contados por k6 vs. suma de `NumberOfMessagesSent` de SQS en la ventana | 0 de diferencia |
| Capacidad por réplica | P0 | Se reporta; calcula las réplicas para 1M de usuarios |

Métricas de CloudWatch para el dashboard y las capturas:
- ALB: `RequestCount`, `TargetResponseTime` (p99), `HTTPCode_Target_5XX_Count`, `HTTPCode_ELB_5XX_Count`, `HealthyHostCount`.
- ECS: `RunningTaskCount` (Container Insights), `CPUUtilization`, `MemoryUtilization`.
- SQS: `NumberOfMessagesSent`, `ApproximateNumberOfMessagesVisible`.

**Conciliación de pérdidas** (`scripts/reconcile`): suma los `202` del JSON de k6, consulta `NumberOfMessagesSent` (suma, periodo de 60 s) entre el inicio y el fin de la corrida más 2 min, y reporta la diferencia. Corre cada escenario sobre una cola recién purgada.

**El ASR1 se cumple** si las cuatro primeras medidas se cumplen en P2. P0 y P3 alimentan el modelo de capacidad.

---

## 10. Riesgos técnicos conocidos

| Riesgo | Por qué importa | Mitigación |
|---|---|---|
| **El target tracking reacciona lento.** Las alarmas evalúan datapoints de 1 min, y la acción de escalado más el arranque de la tarea pueden superar los 3 min | Es el riesgo más probable de fallar el ASR1 | 1) Medir tal cual. 2) Si falla, probar step scaling con una alarma de 1 datapoint. 3) Mitigación de negocio: mínimo programado de réplicas los días 1 y 15. Reportar las tres opciones con datos |
| Arranque lento de Spring Boot | Suma directamente al tiempo de escalado | Medir (§6.3); CDS o imagen más liviana |
| k6 como cuello de botella | Un generador saturado falsea la latencia | Vigilar el CPU de la EC2 (< 70 %) y la métrica `dropped_iterations` de k6 = 0 |
| Cuotas de Fargate | Limitan el máximo de réplicas | Revisarlas antes de P3 |
| Conexiones keep-alive | Pocas conexiones largas pueden desbalancear réplicas nuevas | Revisar la distribución de requests por target; si hace falta, limitar la vida de las conexiones en k6 |
| Carga sintética | Los lotes reales pueden ser más concentrados | Declararlo como limitación; P3 da el margen |

---

## 11. Costos y guardrails

Estimación por corrida completa (P0–P3, ~2 h de entorno, precios on-demand en us-east-1):

| Recurso | Supuesto | USD |
|---|---|---|
| Fargate | Hasta 10 tareas × 0,5 vCPU / 1 GB × 2 h | ~0,49 |
| ALB | 2 h + LCU | ~0,13 |
| EC2 k6 | c5.xlarge × 2 h | ~0,34 |
| SQS | ~1M de envíos | ~0,40 |
| **Total** | | **< 2** |

Guardrails: Budget con alarma a USD 10, etiquetas de costo y `terraform destroy` al final de cada sesión. Nada queda encendido de un día para otro.

---

## 12. Estructura del repositorio

```
poc-ingesta-webhooks/
├── README.md                  ← este documento (resumido) + cómo correr
├── docs/
│   ├── decisiones.md          ← ADRs cortos (Fargate vs EKS, ALB vs NLB, subred pública, P0)
│   └── resultados.md          ← tabla de §13 llena + lectura
├── service/                   ← Spring Boot (Dockerfile multi-stage)
├── load/
│   ├── lib/webhook.js         ← generador de payload + firma HMAC
│   ├── p0-calibracion.js
│   ├── p1-base.js
│   ├── p2-rafaga.js
│   └── p3-estres.js
├── infra/                     ← Terraform por módulos (§7)
├── scripts/
│   ├── build-push.sh          ← build de la imagen y push a ECR
│   ├── run-scenario.sh        ← purga la cola, corre k6 en la EC2 vía SSM y baja los resultados
│   ├── reconcile.sh           ← 202 de k6 vs NumberOfMessagesSent
│   └── collect-metrics.sh     ← exporta las métricas de CloudWatch de la ventana a CSV
└── results/
    ├── raw/                   ← JSON de k6 (en .gitignore si pesa mucho)
    ├── summaries/
    └── screenshots/
```

---

## 13. Plan de trabajo

| Hito | Entregable | Hecho cuando |
|---|---|---|
| M0 · Base | Repo, README, ADRs iniciales | Estructura creada y decisiones de §4 documentadas |
| M1 · Servicio | MS con contrato §6, pruebas unitarias de firma y del ACK después de persistir | Corre local contra LocalStack o una cola real y responde `202/400/401/503` como se especifica |
| M2 · Infra | Terraform `apply` limpio; `destroy` limpio | El servicio responde a través del ALB con 2 réplicas sanas |
| M3 · Humo | P1 corto (5 min) | Tubería completa: k6 → resultados → conciliación con 0 de diferencia |
| M4 · Calibración | P0 | Capacidad por réplica medida y objetivo del target tracking fijado |
| M5 · Pruebas | P1, P2 y P3 completos | Tabla de §9 llena con datos y capturas |
| M6 · Evidencia | `docs/resultados.md`, capturas y video | Listo para pegar en la sección 7.5 y 7.6 del documento |

---

## 14. Plantilla de resultados (para la sección 7.5 del documento)

| Medida del ASR1 | Aceptación | Resultado | ¿Cumple? |
|---|---|---|---|
| p99 a 500/s (P2) | < 300 ms | [__ ms] | [Sí/No] |
| Errores (P1 y P2) | < 0,1 % | [__ %] | [Sí/No] |
| Tiempo de escalado | ≤ 3 min | [__ min] | [Sí/No] |
| Eventos perdidos | 0 | [__] | [Sí/No] |
| Capacidad por réplica (P0) | Se reporta | [__ req/s] | — |

- Réplicas al inicio de P2: [__] · al final: [__] · punto de quiebre en P3: [__ /s]
- Tiempo de arranque de una tarea hasta *healthy*: [__ s]
- Réplicas para el pico a 1M de usuarios: 500 / [capacidad] = [__] (+ [__] % de margen)
- Lectura: [la hipótesis se confirma / no se confirma], [qué medida limitó], [qué implica para producción].

## 15. Evidencia a entregar

- [ ] Enlace al repositorio
- [ ] Resumen de k6 de P1, P2 y P3 (capturas)
- [ ] Gráfica de `RunningTaskCount` y `HealthyHostCount` durante P2
- [ ] Gráfica de `TargetResponseTime` p99 durante P2
- [ ] Salida de `reconcile.sh` con 0 de diferencia
- [ ] Captura del costo real de la corrida (Cost Explorer filtrado por tag)
- [ ] Video de 2–3 min

### Guion del video (2–3 min)

| Tiempo | Contenido |
|---|---|
| 0:00–0:20 | Qué se prueba: el ASR1 en una frase y la hipótesis |
| 0:20–0:40 | Arquitectura de la PoC (diagrama de §5) |
| 0:40–2:10 | P2 en vivo o grabado: k6 subiendo a 500/s y el dashboard con las réplicas aumentando y el p99 estable |
| 2:10–2:40 | Tabla de resultados contra la aceptación y la conciliación de pérdidas |
| 2:40–3:00 | Conclusión: ¿se sostiene la hipótesis? ¿Qué cambiaría en producción? |

---

## 16. Cómo usar este documento con un asistente de código

Trabaja por hitos (§13), uno a la vez, y valida el "Hecho cuando" antes de pasar al siguiente. Las reglas de §6.2 son restricciones duras: si una implementación las rompe (por ejemplo, encolar en memoria o agrupar en lotes), la prueba deja de medir el ASR1. Cada decisión que se aparte de este documento va a `docs/decisiones.md` con su razón.
