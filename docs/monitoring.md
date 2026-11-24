# Monitoreo en vivo

Dashboard web de **solo lectura** para ver qué ocurre en cada componente mientras corre una prueba.

```bash
./scripts/dashboard.sh        # abre http://localhost:8765  (terminal aparte, mientras corren las pruebas)
```
La primera vez crea `.venv` con `boto3`. Si el clúster se creó con otro kubeconfig, usa `KUBECONFIG=<ruta> ./scripts/dashboard.sh`.

## Qué muestra
| Zona | Contenido |
|---|---|
| Flujo de extremo a extremo | Proveedores/k6 → MS de ingesta → cola SQS → Lambda → DynamoDB, con la cifra viva de cada etapa y su color (verde/ámbar/rojo) |
| Indicadores | Tráfico, p99 del MS, p99 del `SendMessage` a SQS, errores, réplicas listas/deseadas, CPU del HPA, cola, DLQ |
| Gráficas (2, 5 o 15 min) | req/s · p99 con la línea de 300 ms · réplicas listas vs deseadas · CPU % con el objetivo de 80 % · cola y DLQ · errores con el límite de 0,1 % |
| Detalle por réplica | Nodo, estado, CPU (con la marca del *request*), req/s y p99 de cada pod |
| Eventos | Decisiones del HPA, pods nuevos, cambios de réplicas listas, DLQ y estado de la Lambda |

El indicador de arriba a la derecha resume: **verde** dentro de los criterios del ASR1, **ámbar** escalando o CPU sobre el objetivo,
**rojo** p99 > 300 ms, errores > 0,1 % o mensajes en la DLQ.

## Cómo funciona (y por qué no altera la medición)
- Consulta el API de Kubernetes y las métricas Prometheus de cada pod por el proxy del API server, cada 2 s (unos 80 KB por pod).
- Calcula req/s y p99 a partir de la diferencia entre dos lecturas de los contadores e histogramas de Micrometer (estimación por buckets).
- Consulta SQS, DynamoDB y Lambda en LocalStack. No escribe nada.

## Terminal (alternativa ligera)
```bash
watch -n2 'kubectl get hpa,pods -o wide'      # escalado
watch -n2 'kubectl top pods'                  # CPU y memoria por pod
```

## Para el video
Abrir el dashboard a pantalla completa, elegir la ventana de 5 min y lanzar `./scripts/run-scenario.sh p2` en otra terminal.
Se ve el tráfico subir de 125 a 500/s, el CPU superar el 80 %, las decisiones del HPA en *Eventos*, las réplicas nuevas pasar a *Ready*
y el p99 respecto de la línea de 300 ms.
