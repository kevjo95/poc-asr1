# ADR 0007 · Lambda de conciliación con idempotencia por estados
Estado: aceptada

**Decisión.** Una Lambda consume la cola y registra cada evento con escritura condicional en DynamoDB:
EN_PROCESO (con expiración) y COMPLETADO. Un duplicado COMPLETADO se descarta; un EN_PROCESO vencido se reintenta.
**Por qué.** Permite conciliar "0 perdidos" en dos niveles (enviados a SQS y procesados) y probar la idempotencia
del ASR2 sin ampliar la hipótesis del ASR1. No publica en un bus: ese componente queda fuera.
