# F4 · 0 perdidos de punta a punta

**Objetivo.** Probar la regla "confirmar después de persistir": todo `202` entregado por el MS debe terminar procesado.

**Preparación.** F1 aplicada, una instancia del MS conectada a LocalStack. El script purga cola y tabla.

**Comando.** `N=500 PAR=20 ./scripts/f4-cero-perdidos.sh`

**Criterio.** `202 - COMPLETADO = 0`, `EN_PROCESO = 0`, DLQ vacía y ningún código distinto de 202.

**Resultado (local).** 500 webhooks en 3 s con paralelismo 20: `202=500`, `COMPLETADO=500`, diferencia **0**: **OK**.
Evidencia: `results/summaries/f4-cero-perdidos-local.txt`.

**Alcance y límites.** Valida la lógica y la conciliación, no el rendimiento: una sola réplica, sin HPA y con
`curl` como generador. La medida contra el ASR1 se hará con k6 en P1 a P3.
