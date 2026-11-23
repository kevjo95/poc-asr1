# ADR 0004 · HPA con la configuración observada en producción
Estado: aceptada

**Decisión.** Mínimo 4 y máximo 8 réplicas; métrica CPU al 80 % del request; al subir: sin ventana de
estabilización y hasta 4 pods por 90 s; al bajar: 300 s de estabilización y hasta 4 pods por 90 s.
**Por qué.** Es la configuración que existe; validar otra cosa no respondería la hipótesis.
**Consecuencia.** Si 8 réplicas no sostienen 500/s con p99 < 300 ms, el resultado es recomendar subir el máximo.
