# ADR 0006 · Perfil de recursos reducido en el entorno local
Estado: propuesta

**Contexto.** El pod de referencia pide 3 GiB; 8 pods exceden la memoria de un equipo de 24 GiB junto con k6 y LocalStack.
**Decisión.** Mantener idéntico lo que define el comportamiento (4-8 réplicas, CPU 80 % del request, ventanas) y
reducir en proporción los recursos: request 100m, limit 500m, memoria 1 GiB, heap 512 MiB.
**Consecuencia.** Los resultados de capacidad absoluta no se extrapolan a producción; sí la forma del escalado.

## Enmienda tras la primera corrida de P0
Con 768 MiB (heap 512 MiB) el pod fue terminado por **OOMKilled** (código 137) a ~370 req/s mientras su CPU no pasaba de
162m de 500m: el perfil dejó menos holgura de memoria que producción (heap de 2 GiB en 3 GiB). La sobrecarga de la JVM
(metaspace, pilas, búferes directos, Tomcat) no escala de forma proporcional. Se sube el límite a **1 GiB** con el mismo heap y se
añade `timeoutSeconds: 3` a las sondas, porque 1 s reinició el pod ante pausas de GC bajo carga. Los resultados de esa corrida
(`p0-20261123-193100`) se descartan para dimensionar.
