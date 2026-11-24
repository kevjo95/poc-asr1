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
- [ ] **A1 · IaC, solo escribir y planificar (yo).** Nuevo entorno `infra/envs/aws-eks` y módulos `network`, `eks`, `ecr`, `irsa`. Decisión por aprobar: usar los módulos públicos
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
