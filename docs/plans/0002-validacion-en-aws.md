# Plan 0002 · Validar el ASR1 en una cuenta AWS personal

Estado: **borrador, pendiente de aprobación** · No se crea ningún recurso en AWS hasta que se confirme cada fase.

## Por qué
En kind no se puede medir el tramo que más pesa en el criterio «réplicas nuevas atendiendo ≤ 3 min»: **aprovisionar un nodo nuevo** (autoescalado de nodos,
arranque de la instancia, descarga de la imagen). Tampoco se miden las cuotas reales de SQS ni el balanceador. Un resultado en AWS es el único comparable con producción.
Además permite correr la Lambda de conciliación **durante** la carga sin competir por CPU con SQS (en LocalStack la contaminaba), con lo que se cierra el escenario combinado
que se dejó fuera en local.

## Alcance mínimo (lo más barato que valida la hipótesis)
| Componente | Elección | Nota |
|---|---|---|
| Red | VPC con 2 AZ y subredes **públicas** (sin NAT) | El NAT cuesta más que todo lo demás junto en una sesión corta |
| Clúster | EKS (versión soportada más reciente) | Plano de control ≈ US$0,10/h |
| Nodos del MS | Grupo gestionado de instancias de 2 vCPU / 8 GiB, mínimo 4 nodos | Reproduce «4 pods en 4 nodos» observado en producción |
| Autoescalado de nodos | Cluster Autoscaler | Es lo que decide si 8 réplicas caben dentro de 3 min |
| Generador de carga | k6 en un grupo de nodos aparte (con *taint*) dentro de la misma VPC | Que el generador no compita con el MS |
| Imagen | ECR + `docker push` de `ingest-ms:0.2.0` | |
| Permiso a SQS | Rol IAM asociado al pod (IRSA), solo `sqs:SendMessage` a esa cola | Reemplaza las credenciales de prueba de LocalStack |
| Entrada | Servicio `LoadBalancer` interno (NLB) | Mide el camino real del tráfico |
| Cola, DLQ, tabla, Lambda | `infra/envs/aws` ya existente | Se activa la Lambda durante la carga |
| Perfil del MS | El de producción: request 200m / límite 2000m, 3096 MiB, HPA 4–8, CPU 80 % | No el perfil reducido de kind |

**Fuera de alcance:** malla de servicios, WAF, dominios, HTTPS público, múltiples regiones.

## Estimación de costo (orden de magnitud; confirmar con la calculadora de precios antes de aplicar)
Precios aproximados de us-east-1, bajo demanda: plano EKS ≈ 0,10 USD/h; 4 nodos de 2 vCPU ≈ 0,4 USD/h; nodos extra en la ráfaga ≈ 0,4 USD/h mientras existan;
generador ≈ 0,2 USD/h; NLB ≈ 0,03 USD/h. **Total ≈ 0,8–1,2 USD/h.** Una sesión de 4–5 h con todo encendido ≈ **4–6 USD**; SQS y Lambda son céntimos a este volumen.
Riesgo principal: **olvidar destruir**. Mitigación: alarma de presupuesto (ya existe, 10 USD por defecto), etiquetas en todo, fase final de `destroy` con verificación.

## Fases (con punto de parada: no se avanza sin tu confirmación)
- [ ] **A0 · Requisitos (tú).** Cuenta personal de AWS con método de pago; usuario/rol administrativo temporal vía IAM Identity Center (`aws configure sso`) o usuario IAM propio;
  confirmar el límite de vCPU de instancias bajo demanda (cuentas nuevas a veces parten con pocas) y pedir aumento si hace falta.
  **Nunca usar un perfil de trabajo.** Criterio: `aws sts get-caller-identity --profile <perfil>` muestra tu cuenta personal.
- [x] **A1 · IaC, solo escribir y validar (hecho el 23-nov, sin cuenta).** Nuevo entorno `infra/envs/aws-eks` y módulos `network`, `eks`, `ecr`, `irsa`. Decisión por aprobar: usar los módulos públicos
  `terraform-aws-modules` (más rápido, nueva dependencia) o recursos propios (más líneas, sin dependencia). Criterio: `terraform validate` y `terraform plan` limpios, plan revisado por ti.
- [ ] **A2 · Aplicar la base (yo, con tu OK).** Red, EKS, ECR, cola, tabla, Lambda y alarma de presupuesto. Criterio: nodos `Ready`, `kubectl get nodes` y el correo de la alarma confirmado.
- [ ] **A3 · Desplegar el MS (yo).** Subir imagen a ECR, instalar metrics-server y Cluster Autoscaler, Helm con el perfil de producción y IRSA. Criterio: 4 pods `Ready` y `202` real contra la SQS de AWS.
- [ ] **A4 · Pruebas funcionales en AWS (yo).** F2–F4 adaptadas (conciliación contra `NumberOfMessagesSent` de CloudWatch). Criterio: 0 perdidos.
- [ ] **A5 · Carga (yo).** P0 (capacidad por réplica), P2 (la ráfaga del ASR1) y, si el presupuesto lo permite, P3. P1 de 30 min es opcional. Criterio: informe por escenario con evidencia.
- [ ] **A6 · Evidencia y documento.** Capturas, informes y `docs/cambios-al-documento.md` actualizado con lo comparado frente a local.
- [ ] **A7 · Destruir (yo, con tu OK) y verificar.** `terraform destroy`, revisar que no queden nodos, balanceadores, volúmenes ni IP elásticas, y mirar Cost Explorer al día siguiente.

## Criterios de éxito
Los mismos del ASR1: p99 < 300 ms a 500 req/s, errores < 0,1 %, réplicas nuevas (incluyendo nodo nuevo) atendiendo en ≤ 3 min, 0 perdidos medidos con `NumberOfMessagesSent`.
Si no se cumplen, se documenta la causa y la recomendación de cambio (como en el enfoque AS-IS → TO-BE).

## Riesgos
| Riesgo | Mitigación |
|---|---|
| Cuota de vCPU insuficiente en cuenta nueva | Verificarla en A0 y pedir aumento con antelación |
| Costo por olvidar recursos | Alarma de presupuesto, etiquetas, fase A7 obligatoria |
| El nodo nuevo tarda > 3 min | Es un resultado válido: recomendar nodos de reserva, sobreaprovisionamiento o Karpenter |
| Imagen grande tarda en descargarse en cada nodo nuevo | Medirlo por separado; evaluar CDS/AppCDS o imagen más pequeña |
| Credenciales o identificadores en el repositorio | El hook anti-fugas sigue activo; variables por perfil, nada de IDs en archivos versionados |

## Decisiones que necesito de ti
1. ¿Apruebas este alcance y el orden de fases?
2. ¿Módulos públicos de Terraform (más rápido) o recursos propios (sin dependencia nueva)?
3. ¿Cuándo tendrías la cuenta y el perfil listos (A0)? No avanzo a A2 sin eso.

## Estado de A1 (preparado sin tocar AWS)
Hecho y validado localmente (`terraform validate`, `terraform fmt`, `helm lint` y `helm template`); **no se ha ejecutado `plan` ni `apply`** porque requieren credenciales.

| Pieza | Dónde |
|---|---|
| Terraform: VPC pública, EKS (módulo 20.37.2), 2 grupos de nodos, ECR, IRSA, cola/DLQ/tabla/Lambda, presupuesto | `infra/envs/aws-eks/` |
| Chart: ServiceAccount con rol IRSA, `nodeSelector`, NLB interno, perfil de producción | `deploy/helm/ingest-ms/values-aws.yaml` |
| Subir y desplegar el MS; bajar y verificar residuos | `scripts/aws-up.sh`, `scripts/aws-down.sh` |
| k6 en el grupo de nodos de carga | `K6_TARGET=aws ./scripts/k6-incluster.sh` |

**Decisiones tomadas al prepararlo (revisables):**
1. **Módulos públicos** `terraform-aws-modules` (vpc 5.21.0, eks 20.37.2, iam 5.60.0), fijados a las versiones cuya interfaz se conoce; nueva dependencia aceptada por defecto, se puede reemplazar por recursos propios.
2. **Nodos Graviton (arm64)** `m7g.large` para el MS y `c7g.xlarge` para el generador: la imagen se compila en Apple Silicon (arm64) y así evita imágenes multi-arquitectura; además es más barato por hora.
3. **Nodos llenos a propósito:** con 3096 MiB por pod caben 2 por nodo; 4 pods llenan los 2 nodos mínimos y la ráfaga obliga al Cluster Autoscaler a crear nodos nuevos. Es la medición de nodo nuevo que kind no puede dar.
4. **`cluster_version` sin valor por defecto:** una versión fuera del soporte estándar cuesta ~6 veces más por hora en el plano de control. Se elige tras consultar `aws eks describe-cluster-versions`.
5. **Sin NAT Gateway** y balanceador **interno**: el generador corre dentro de la VPC.

**Pendiente para A5 (carga en AWS):** adaptar `run-scenario.sh` para AWS (conciliación contra `NumberOfMessagesSent` de CloudWatch, Lambda activa, sin `kind`), y el dashboard para leer SQS real.
**Riesgos conocidos a verificar con la cuenta:** que la imagen del Cluster Autoscaler coincida con la versión de Kubernetes (`CA_IMAGE_TAG`), que 2 pods de 3096 MiB quepan por nodo `m7g.large` (memoria asignable), y la cuota de vCPU.

## Actualización 23-nov (perfil listo, verificado en solo lectura)
Cuenta en **plan gratuito con créditos (120 USD, vencen 23-may-2027)**; acceso con `aws login` (usuario IAM + MFA, sin llaves). Verificado: identidad correcta, presupuesto mensual de 20 USD con alertas, EKS 1.36 en soporte estándar hasta ago-2027.
Restricciones nuevas y su efecto en el diseño (**reemplazan las decisiones 2 y 4 de arriba**):
| Restricción | Efecto |
|---|---|
| Tipos permitidos: `m7i-flex.large` (MS) y `c7i-flex.large` (carga), ambos x86_64 | Se abandona Graviton; imagen `linux/amd64`; el Dockerfile compila con Maven en la arquitectura del equipo |
| Cuota de vCPU = 5 (aumento a 32 pendiente) | Modo **cuota-5**: 2 nodos del MS, sin nodo de carga (k6 en los nodos del MS), perfil `values-aws-lite.yaml` (1 GiB por pod). No mide nodo nuevo |
| Modo completo (cuota ≥ 32) | `ms_max_nodes` hasta 9, `load_enabled = true`, perfil de producción de 3096 MiB |
| No usar Organizations ni Identity Center | Perfil puente `poc-asr1-tf` (`credential_process`) para que Terraform use la sesión de `aws login` |
| Presupuesto ya existe | `create_budget = false` por defecto |

`terraform plan` en modo cuota-5: **63 a crear, 0 a cambiar, 0 a destruir** (sin NAT ni IP elásticas). Pendiente: aprobación explícita para `apply` (A2).
