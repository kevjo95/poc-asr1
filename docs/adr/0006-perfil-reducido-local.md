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

## Enmienda 2 · tras el intento 1 de P2 (CPU)
Con request **100m** el servicio consume ~3,6m de CPU por cada req/s: 4 pods superan el 80 % del request hacia ~90 req/s, de modo que el HPA
reaccionaba al tráfico **base** (125/s) y no a la ráfaga. En producción el servicio está al ~1 % de CPU en reposo, así que el perfil
reducido distorsionaba la dinámica que se quería validar.
**Decisión:** request **300m** / límite **1000m** (memoria 1 GiB sin cambio). El umbral del HPA (80 % = 240m) cae en ~65 req/s por pod, es decir
~265 req/s con 4 pods: el tráfico base de 125/s no escala y la ráfaga a 500/s sí.
**Consecuencia:** la capacidad por réplica de P0 medida con 500m de límite deja de valer y se repite. Además cada corrida añade un **pre-calentamiento**
(40 req/s, 90 s) y espera que el HPA se estabilice en 4 réplicas con CPU < 60 % antes de medir, porque el arranque en frío de la JVM (CPU > 150 %)
dispara el escalado.

## Enmienda 3 · corrección de la enmienda 2 (tras el intento 2 de P2)
La enmienda 2 se apoyó en "~3,6m de CPU por req/s", cifra tomada con la **JVM en frío**. Ya pre-calentada, el MS gasta ~**1m por req/s**
(a 125 req/s por pod: ~43 % de 300m ≈ 130m). Consecuencias medidas en P2 intento 2 (request 300m): con 4 réplicas el CPU nunca pasó de 43 %,
el HPA no escaló y la ráfaga a 500/s se absorbió sin añadir pods; por tanto no se pudo medir el tiempo de escalado.
Con el servicio ya caliente, **request 100m** deja el umbral del HPA (80m) en ~80 req/s por pod: el tráfico base (31 req/s por pod con 4 réplicas)
queda en ~31 % y los 125 req/s por pod de la ráfaga en ~125 %, de modo que el HPA sí reacciona a la ráfaga y no a la base.
**Decisión:** request **100m**, límite **1000m** (relación 1:10 como en producción, 200m/2000m); memoria 1 GiB. El intento 1 de P2 escaló
por el arranque en frío, no por la carga base; el pre-calentamiento (enmienda 2) ya lo corrige y se mantiene.

## Enmienda 4 · límite de CPU 2000m
La JVM ve tantos CPUs como el límite del contenedor: con ≤ 1000m ve 1 y la réplica aguanta ~200-300 req/s; con 2000m ve 2 y aguanta ~400 (experimento E0-E3).
Producción usa 2000m. **Decisión final del perfil local:** request 100m / **límite 2000m** / memoria 1 GiB (heap 512 MiB).
