# Recorrido para ejecutar y grabar la validación en AWS

Una sola sesión, de principio a fin, con el orden exacto, lo que se ve en la consola de AWS y lo que se dice en cada escena.
Todo `apply` y el `destroy` final requieren confirmación explícita. Nada de lo que se muestra debe incluir el ID de cuenta (ver «Antes de grabar»).

## 0 · Antes de grabar (una vez)
- [ ] `aws login --profile poc-asr1` y `aws sts get-caller-identity --profile poc-asr1` muestra `user/kevjo-poc`. Perfil puente `poc-asr1-tf` en `~/.aws/config`.
- [ ] Cuota de vCPU: si sigue en 5, se graba el **modo cuota-5** (2 nodos, sin nodo nuevo). Si llegó a 32, **modo completo** (se ve el nodo nuevo, que es la mejor escena).
- [ ] `cp infra/envs/aws-eks/terraform.tfvars.example infra/envs/aws-eks/terraform.tfvars` y elegir un preset (el archivo no se versiona).
- [ ] **Ocultar el ID de cuenta:** en la consola, menú de la cuenta → desactivar «Show account ID» (o recortar la esquina superior derecha en la edición). El ID aparece en la barra superior y en las URL de ECR.
- [ ] Región de la consola: **us-east-1 (N. Virginia)** en todas las pestañas.
- [ ] **Ensayo local** del dashboard y del guion en kind (gratis): `./scripts/dashboard.sh` y `./scripts/run-scenario.sh p2`.
- [ ] Pestañas de la consola abiertas de antemano (sección 2), el panel de CloudWatch ya favorito.

## 1 · Línea de tiempo de la sesión (≈ 2,5–3 h; ≈ 1–2 USD con todo encendido, confirmar en Cost Explorer)
| Min | Qué pasa | Se graba |
|---|---|---|
| 0 | `terraform apply` (tras tu OK) | Sí, 1 min: el plan «64 a crear» y la confirmación. El resto se acelera |
| 0–15 | Se crea el EKS y sus nodos | Consola: EKS → estado `Creating` → `Active`; EC2 → instancias apareciendo |
| 15–25 | `./scripts/aws-up.sh`: imagen a ECR, metrics-server, Autoscaler, MS | Corto. Consola: ECR con la imagen, EKS → Workloads |
| 25 | Prueba funcional: un `curl` firmado devuelve 202 y el mensaje aparece en SQS | Sí: consola SQS → *Send and receive messages* → *Poll* |
| 30 | `TARGET=aws ./scripts/dashboard.sh` en otra terminal | Sí, es la pantalla principal |
| 35–70 | `TARGET=aws ./scripts/run-scenario.sh p0` (capacidad por réplica) | Resumen |
| 75–110 | `TARGET=aws ./scripts/run-scenario.sh p2` (la ráfaga del ASR1) | **Escena central** |
| 115 | Informe + conciliación + CloudWatch | Sí |
| 125 | `./scripts/aws-down.sh` (con tu OK) y verificación | Sí: consola vacía y Cost Explorer |

## 2 · Qué mostrar en la consola de AWS (y para qué)
| Servicio (buscar en la barra) | Dónde mirar | Qué demuestra |
|---|---|---|
| **EKS** | Clusters → `poc-asr1` → *Resources* (Workloads, Pods) y *Compute* (nodegroups) | La infraestructura montada: grupos de nodos, versión 1.36, add-ons |
| **EC2 → Instances** | Filtro de etiqueta `project = poc-asr1` | Los nodos reales (`m7i-flex.large`); en modo completo, **aparecer un nodo nuevo en la ráfaga** |
| **EC2 → Auto Scaling groups** | grupo del nodegroup `ms` → pestaña *Activity* | Historial «Launching a new EC2 instance» con hora: es la medición del tiempo de nodo nuevo |
| **EC2 → Load Balancers** | NLB → *Listeners* y *Target health* | Camino real del tráfico; targets sanos |
| **ECR** | Repositorios → `poc-asr1/ingest-ms` | La imagen publicada y su tag |
| **SQS** | cola `poc-asr1-ingest` → pestaña *Monitoring*; DLQ aparte | Mensajes enviados/recibidos; la DLQ debe quedar en 0 |
| **Lambda** | `poc-asr1-reconciler` → *Monitor* | Invocaciones y errores durante la carga (activa, a diferencia de local) |
| **DynamoDB** | Tables → `poc-asr1-idempotency` → *Explore items* | Eventos `COMPLETADO` (idempotencia). El conteo de ítems tarda ~6 h en actualizarse: usar *Explore items* |
| **CloudWatch → Dashboards** | `poc-asr1` (lo crea Terraform) | Un solo panel: enviados/min, cola y edad, Lambda, DLQ, escrituras a DynamoDB |
| **CloudWatch → Metrics → SQS** | `NumberOfMessagesSent` | La cifra oficial para la conciliación nivel 1 (llega con 1–3 min de retraso) |
| **IAM → Roles** | `poc-asr1-ingest-ms` → *Permissions* | Un solo permiso: `sqs:SendMessage` sobre esa cola (mínimo privilegio, IRSA) |
| **Billing → Cost Explorer / Budgets** | Al final y al día siguiente | Cuánto costó la sesión y que el presupuesto no saltó |

Sugerencia de pantalla: mitad izquierda el dashboard local (`http://localhost:8765`), mitad derecha la consola (panel de CloudWatch o EC2); la terminal con `run-scenario` se muestra al inicio y al final.

## 3 · Guion por escenas
1. **Contexto (30 s).** ASR1: 500 req/s sostenidos, p99 < 300 ms, errores < 0,1 %, réplicas nuevas atendiendo en ≤ 3 min, 0 webhooks perdidos.
2. **Infraestructura (1–2 min).** Terraform → consola EKS, EC2, ECR, SQS, IAM (tabla de arriba). Frase clave: *«Todo se creó con código y se destruirá al terminar»*.
3. **El MS sano (1 min).** Dashboard: 4 réplicas, CPU baja, 0 errores. `curl` firmado → 202 → mensaje en SQS.
4. **P2, la ráfaga (5–8 min).** Dashboard con el banner del escenario. Señalar en vivo: (a) req/s sube 125 → 500; (b) CPU supera 80 %; (c) el HPA decide 4 → 8 (panel de eventos); (d) **pods `Pending` → nodo nuevo → Ready** (modo completo) con el tiempo «Creado → Ready» del panel de nodos y la *Activity* del Auto Scaling group; (e) p99 y errores contra los umbrales.
5. **Conciliación (1–2 min).** Informe del script: 202 de k6 = `NumberOfMessagesSent` de CloudWatch; Lambda procesó todo; DLQ = 0. Mostrar el panel de CloudWatch.
6. **Veredicto (1 min).** Leer el informe generado en `results/summaries/`: qué criterios se cumplen y cuáles no, y la recomendación (AS-IS → TO-BE).
7. **Cierre y costo (1 min).** `aws-down.sh`, verificación vacía, Cost Explorer.

## 4 · Comandos de la sesión (en orden)
```bash
aws login --profile poc-asr1
cd infra/envs/aws-eks && AWS_PROFILE=poc-asr1-tf terraform apply     # confirma tú: escribe "yes" tras revisar el plan
cd ../../.. && AWS_LITE=1 ./scripts/aws-up.sh                          # AWS_LITE=1 solo en modo cuota-5; anota el secreto HMAC que imprime
export INGEST_HMAC_SECRET=<el secreto impreso>                         # no lo guardes en el repo
TARGET=aws ./scripts/dashboard.sh                                      # otra terminal
TARGET=aws K6_NODE_ROLE=ms ./scripts/run-scenario.sh p0                # K6_NODE_ROLE=ms solo en modo cuota-5 (no hay nodo de carga)
TARGET=aws K6_NODE_ROLE=ms ./scripts/run-scenario.sh p2
./scripts/aws-down.sh                                                  # destruye y verifica residuos (te pide confirmación)
```

## 5 · Límites honestos de cada modo
| | Modo cuota-5 | Modo completo (cuota ≥ 32) |
|---|---|---|
| Nodos | 2 fijos, k6 comparte nodos con el MS (el generador compite por CPU) | MS autoescalable y nodo de carga aparte |
| Perfil del MS | Lite: 1 GiB por pod | Producción: 3096 MiB |
| Tiempo de nodo nuevo | **No medible** | **Medible** (Auto Scaling *Activity* + panel de nodos) |
| Valor | HPA, camino real a SQS, Lambda activa, conciliación con CloudWatch | Cierra el criterio de ≤ 3 min completo |

## 6 · Si algo sale mal durante la grabación
- Pods en `Pending` sin nodo nuevo en modo cuota-5: es lo esperado (no hay cuota ni autoescalado); documentarlo, no es un fallo.
- `aws-up.sh` falla en el Cluster Autoscaler: fijar `CA_IMAGE_TAG` a una versión `v1.36.x` publicada; el MS no depende de él en modo cuota-5.
- Se acerca una alerta de presupuesto: parar, `aws-down.sh`, avisar.
- Credenciales caducadas: `aws login --profile poc-asr1` de nuevo.
