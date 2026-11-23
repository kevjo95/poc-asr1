# F1 · Infraestructura reproducible

**Objetivo.** Crear y destruir la infraestructura (cola + DLQ, tabla de idempotencia, Lambda con su mapping)
con un solo Terraform y dos destinos.

**Preparación.** `docker compose -f infra/local/docker-compose.yml up -d` (LocalStack comunitario).

**Comando.** `cd infra/envs/local && terraform init && terraform apply -auto-approve`

**Criterio.** 7 recursos creados sin error; `terraform validate` correcto también en `infra/envs/aws`.

**Resultado (local).** `Apply complete! Resources: 7 added`. `infra/envs/aws`: `validate` correcto
(no se ejecuta `apply` en AWS; ver ADR 0003).

**Pendiente.** Verificar `destroy` limpio y repetir el `apply` desde cero.
