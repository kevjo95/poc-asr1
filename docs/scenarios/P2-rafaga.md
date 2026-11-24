# P2 · Ráfaga de nómina (ASR1)

**Objetivo.** 125 → 500 req/s en 1 min, sostenido 5 min, con HPA activo (4–8, CPU 80 % del request). Evalúa p99 < 300 ms, errores < 0,1 %,
escalado ≤ 3 min y 0 mensajes perdidos. Comando: `./scripts/run-scenario.sh p2`.

## Intento 1 (`p2-20261123-200050`) · NO CONCLUYENTE
Evidencia: `results/summaries/p2-20261123-200050-informe.md`, capturas en `docs/scenarios/evidence/p2-intento1/`, datos crudos en `results/raw/` (no versionado).

| Fase | Vista de k6 (cliente) | Vista del MS (dashboard) |
|---|---|---|
| Sostenido 500/s | p99 1609 ms · errores 0,89 % | p99 ≈ 3–90 ms · 0 % errores (un pico de 1760 ms) |
| Réplicas | 8 desde el primer minuto | 4 → 8 durante el **calentamiento** |
| Conciliación nivel 1 | 241.713 `202` vs 242.504 mensajes en SQS (+791, sin pérdidas de lo confirmado) | DLQ 0, `EN_PROCESO` 0 |

**Por qué no es concluyente.**
1. **El tiempo de escalado no se midió.** El HPA subió a 8 réplicas en el calentamiento (CPU 175–184 % al arrancar: JVM en frío y, además, ~3,6 m de CPU por req/s
   con un *request* de solo 100m, es decir, 4 pods ya superan el 80 % hacia ~90 req/s). La ráfaga encontró 8 réplicas ya listas y el "0 s" del informe no tiene valor.
2. **El perfil local de CPU no es proporcional al de producción.** Con request 100m el HPA reacciona al tráfico base (125/s), cuando en producción el
   servicio está al ~1 % de CPU en reposo. El escalado deja de ser una respuesta a la ráfaga.
3. **El p99 de k6 no coincide con el del MS.** Con 8 réplicas el MS reporta p99 de decenas de ms y 0 % de errores, pero k6 ve 825 ms de p95 y 0,89 % de fallos
   (más 709 iteraciones descartadas). Los fallos ocurren antes de la aplicación: ruta anfitrión → Docker Desktop (NodePort) o saturación del generador/equipo
   compartido. Hay que aislar esta variable antes de atribuir nada al diseño.

**Lo que sí se sostiene:** 0 mensajes perdidos de lo confirmado, DLQ 0, sin reinicios ni OOM, pods nuevos *Ready* en 9–11 s.

## Cambios propuestos para el intento 2
- Recalibrar request/límite de CPU para que el HPA no actúe en la carga base (ver ADR 0006, enmienda).
- Pre-calentar la JVM y esperar a que el HPA se estabilice en 4 réplicas antes de medir el escalado.
- Medir el camino cliente→pod (generador y NodePort) para separar el ruido del entorno del comportamiento del MS.

## Intento 2 (`p2-20261123-202502`) · NO CONCLUYENTE (escalado) · evidencia: `docs/scenarios/evidence/p2-intento2/`
Con pre-calentamiento y espera de estabilidad (HPA en 4 réplicas, CPU < 60 %) y request de CPU 300m.

| Fase | Vista de k6 | Vista del MS (dashboard) |
|---|---|---|
| Calentamiento 125/s | p99 8 ms · 0 % | p99 3–8 ms · 0 % |
| Ráfaga 125→500/s | p99 512 ms · 0 % | p99 3–62 ms |
| Sostenido 500/s | p95 130 ms · **p99 1273 ms** · errores 0,098 % | p99 3–150 ms · 0 % · CPU 29–43 % |
| Retorno | p99 1971 ms · 0,76 % | p99 3–51 ms |

- **0 mensajes perdidos:** 242.639 `202` frente a 243.069 mensajes en SQS (+430 por reintentos tras timeout del cliente), DLQ 0, `EN_PROCESO` 0.
- **Errores incluida la ráfaga: 0,071 %** (cumple < 0,1 %), pero con margen mínimo y concentrados en el retorno.
- **No hubo escalado:** 4 réplicas absorbieron 500/s con CPU ≤ 43 % del request de 300m. El tiempo de escalado **no se midió** (ver ADR 0006, enmienda 3: con la JVM caliente el costo es ~1m por req/s y 300m era demasiado alto).
- **p99 de k6 vs MS:** por segunda vez k6 mide 1,3–2 s de p99 mientras el MS responde en decenas de ms, con 4 y con 8 réplicas, y con 680 iteraciones descartadas. La latencia está en el camino cliente→pod (k6 y Docker Desktop comparten el equipo con el clúster), no en el servicio.

## Intento 3 previsto
- Request **100m** / límite 1000m (ADR 0006, enmienda 3) para que el HPA reaccione a la ráfaga.
- Generador de carga **dentro del clúster** (k6 como Job que ataca el Service) para eliminar Docker Desktop y la competencia por CPU con el equipo.

## Intento 3 (`p2-20261123-221301`) · el escalado se mide; latencia y errores los condiciona el emulador de SQS
Perfil final: Java 25, hilos de plataforma, request 100m / límite 2000m, generador **dentro del clúster**, pre-calentamiento y espera de estabilidad. Evidencia: `docs/scenarios/evidence/p2-intento3/`.

| Fase | Vista de k6 | Vista del MS (dashboard) |
|---|---|---|
| Calentamiento 125/s | p99 22 ms · 0 % | p99 3–9 ms · 0 % |
| Ráfaga | p99 1089 ms · 0 % | p99 4–11 ms |
| Sostenido 500/s | p95 903 ms · p99 1830 ms · 0,64 % | p99 4–11 ms · 0 % salvo **dos picos** (1409 ms y 2101 ms) |
| Retorno | p99 1896 ms · 0,79 % | p99 3–14 ms salvo el pico final (7,8 % de errores) |

- **Escalado:** el HPA reaccionó a la ráfaga: 6 → 7 → 8 réplicas, la última *Ready* a **86 s** del inicio de la ráfaga (criterio ≤ 3 min). Los pods nuevos tardaron **5 s** en estar *Ready*.
  Salvedad: ya había 6 réplicas al empezar la ráfaga porque con request de 100m el tráfico base (125/s, ~62 % del request) cruzó el 80 % con ruido durante el calentamiento. En kind no existe el tramo de nodo nuevo.
- **0 perdidos:** 241.732 `202` frente a 242.877 mensajes en SQS (+1.145 por reintentos tras timeout del cliente), DLQ 0, `EN_PROCESO` 0.
- **De dónde sale la latencia de k6.** Salvo los picos, el MS responde en ~5 ms. En los dos picos el p99 del MS es **idéntico** al p99 de su propio `SendMessage` a SQS
  (1409,2 = 1409,2 ms; 2101,4 = 2101,4 ms): el tiempo se pierde dentro de la llamada a SQS, no en el MS. Con la cola creciendo a ~243.000 mensajes, el emulador (LocalStack) sufre
  paradas de segundos; el MS responde con `503`/espera y k6 las ve como cola de peticiones y timeouts.
- **Veredicto local:** el escalado del HPA cumple y el MS no es el cuello de botella; el p99 y los errores del ASR1 **no se pueden concluir** en local porque el sustituto de SQS no sostiene 500 mensajes por segundo de forma estable.

## Siguiente paso
Repetir P2 sustituyendo el SQS de LocalStack por un servidor compatible más rápido (ElasticMQ) solo para la ruta de ingesta, y, en paralelo, la corrida en AWS (plan 0002), donde SQS real
no tiene este límite. Subir el request de CPU a 200m (como producción) para que el tráfico base no cruce el umbral del HPA.
