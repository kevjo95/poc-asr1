# F2 · Idempotencia de la Lambda de conciliación

**Objetivo.** Un evento duplicado no genera efectos duplicados; un evento nuevo termina `COMPLETADO`.

**Preparación.** Infra local aplicada (F1). El script purga cola y tabla antes de correr.

**Comando.** `N=50 D=10 ./scripts/f2-idempotencia.sh`

**Criterio.** Con N únicos y D duplicados: `COMPLETADO = N`, `EN_PROCESO = 0`, filas = N, DLQ = 0.

**Resultado (local).** 60 mensajes (50 únicos, 10 duplicados) -> `COMPLETADO=50`, `EN_PROCESO=0`, `DLQ=0`: **OK**.
Evidencia: `results/summaries/f2-idempotencia-local.txt`.

**Cubierto por pruebas unitarias** (`services/reconciler-lambda/tests`, 7 pruebas): duplicado completado,
duplicado en el mismo lote, falla que deja `EN_PROCESO`, `EN_PROCESO` vigente que no se reclama,
`EN_PROCESO` vencido que se reintenta sin confundirse con duplicado, mensaje sin `eventId`.

**Pendiente.** Variante con falla simulada del 1 % y 5 % de duplicados (parámetros del ASR2).
