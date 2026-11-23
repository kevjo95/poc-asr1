# Plan 0001 · PoC ASR1 local con Terraform apto para AWS

Estado: **en curso** · Base: `PoC-ingesta-webhooks.md`, `docs/spike-01-referencia-productiva.md`

## Objetivo
Probar que el MS de ingesta escala horizontalmente bajo la ráfaga de nómina sin perder webhooks,
en un entorno local (kind + LocalStack) y con la infraestructura lista para repetirse en una cuenta AWS.

## Alcance
MS de ingesta -> cola SQS (+DLQ) -> Lambda de conciliación -> tabla de idempotencia (DynamoDB).
Fuera: API Gateway, WAF, bus, consumidores y la malla de servicios.

## Hitos
- [x] H0 · Repo, kit de IA, spike 01, documento de la PoC
- [ ] H1 · Infraestructura como código en dos destinos (`infra/envs/local` y `infra/envs/aws`), verificada en LocalStack
- [ ] H2 · Lambda de conciliación con idempotencia (EN_PROCESO / COMPLETADO) y pruebas
- [ ] H3 · MS de ingesta (contrato 202/400/401/503, HMAC, ACK tras persistir) y pruebas
- [ ] H4 · Chart de Helm con HPA igual a producción; clúster kind (requiere >= 16 GiB en Docker)
- [ ] H5 · Carga con k6 (P0..P3) y conciliación; evidencias por escenario
- [ ] H6 · Revisión del documento de la entrega con resultados

## Evidencia
Cada escenario tiene su ficha en `docs/scenarios/` con: objetivo, preparación, comando, criterio,
resultado y rutas a `results/`. Los resultados crudos pesados no se versionan (`results/raw/`).

## Restricciones
- Repo público y académico: sin datos, nombres, cuentas ni identificadores de la organización.
- Nada se despliega en AWS sin confirmación explícita; el destino AWS se valida con `terraform validate`/`plan` hasta que haya cuenta.
