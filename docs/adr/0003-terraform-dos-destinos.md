# ADR 0003 · Un solo Terraform con dos destinos (LocalStack y AWS)
Estado: aceptada

**Decisión.** Los módulos de `infra/modules/` son idénticos para ambos destinos. `infra/envs/local`
apunta el proveedor a LocalStack; `infra/envs/aws` usa un perfil de AWS y un presupuesto con alarma.
**Consecuencias.** No se escribe la infraestructura dos veces. El destino AWS se verifica con
`terraform validate` y `plan` mientras no haya cuenta. Nunca se ejecuta `apply` en AWS sin confirmación.
