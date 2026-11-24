# F5 · Despliegue en kind con HPA de producción

**Objetivo.** Desplegar el MS con Helm en un clúster `kind` y verificar que el HPA se comporta como el observado.

**Preparación.** `./scripts/cluster-up.sh` (LocalStack, Terraform, kind con 3 workers, metrics-server, Helm).

**Verificación.** `kubectl get hpa,pods -o wide` y `./scripts/f4-cero-perdidos.sh` contra `localhost:8080` (NodePort).

**Resultado (local).**
- Se despliega 1 réplica y el HPA la lleva al mínimo de **4** (min 4, max 8, CPU 80 % del request).
- CPU en reposo ≈ 5-7 % por pod (en el servicio de referencia ≈ 1 %).
- F4 a través del clúster: 500 webhooks, `202=500`, `COMPLETADO=500`, diferencia 0. Evidencia: `results/summaries/f4-cero-perdidos-kind.txt`.
- 503 provocado pausando LocalStack: respuesta en 2,03 s (timeout explícito) y recuperación sin pérdidas al reanudar.

**Observaciones.**
- Un pod recién arrancado consume ~180m de CPU (arranque de la JVM) frente a un request de 100m; conviene observar
  si el arranque dispara escalados espurios cuando haya carga (se mide en P1/P2).
- Los 4 pods quedaron repartidos en 3 workers (uno con dos): `topologySpread` es preferente (`ScheduleAnyway`).
