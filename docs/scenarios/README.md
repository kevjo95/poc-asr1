# Escenarios y evidencias

Cada escenario tiene una ficha con: objetivo, preparación, comando, criterio, resultado y evidencia.
Los **F** son funcionales (contrato, idempotencia, conciliación). Los **P** son de carga (ASR1).

| Id | Escenario | Estado | Evidencia |
|---|---|---|---|
| F1 | Infraestructura reproducible (apply/destroy) | hecho (local) | `results/summaries/f1-infra-local.txt` |
| F2 | Idempotencia de la Lambda de conciliación | hecho (local) | `results/summaries/f2-idempotencia-local.txt` |
| F3 | Contrato del MS de ingesta (202/400/401/503) | hecho (local) | `results/summaries/f3-contrato-local.txt` |
| F4 | ACK solo después de persistir y 0 perdidos de punta a punta | hecho (local) | `results/summaries/f4-cero-perdidos-local.txt` |
| P0 | Calibración con 1 réplica fija | pendiente | — |
| P1 | Base 125/s, 30 min | pendiente | — |
| P2 | Ráfaga 125 → 500/s | pendiente | — |
| P3 | Estrés hasta el punto de quiebre | pendiente | — |

> Entorno: kind + LocalStack con recursos reducidos en proporción (ADR 0006). Las medidas absolutas
> de p99 y tiempo de escalado son indicativas; ver limitaciones del documento de la PoC.
