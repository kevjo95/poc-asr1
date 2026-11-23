# ADR 0006 · Perfil de recursos reducido en el entorno local
Estado: propuesta

**Contexto.** El pod de referencia pide 3 GiB; 8 pods exceden la memoria de un equipo de 24 GiB junto con k6 y LocalStack.
**Decisión.** Mantener idéntico lo que define el comportamiento (4-8 réplicas, CPU 80 % del request, ventanas) y
reducir en proporción los recursos: request 100m, limit 500m, memoria 768 MiB, heap 512 MiB.
**Consecuencia.** Los resultados de capacidad absoluta no se extrapolan a producción; sí la forma del escalado.
