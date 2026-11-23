# ADR 0002 · Kubernetes local con kind para replicar el despliegue de producción
Estado: aceptada

**Contexto.** Producción corre en Kubernetes con un HPA. El documento original proponía ECS Fargate.
**Decisión.** La PoC corre en un clúster `kind` local con el mismo tipo de HPA.
**Consecuencias.** Se valida el comportamiento del escalado (dinámica, contrato, pérdidas). El p99 y el
tiempo de escalado absolutos no son comparables con producción por compartir recursos de un solo equipo
(ver ADR 0006). Una corrida en AWS queda como extensión (ADR 0003).
