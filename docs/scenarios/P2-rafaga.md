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
