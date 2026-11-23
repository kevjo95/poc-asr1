# ADR 0005 · Base de carga: 1M de usuarios y 900.000 webhooks en 2 h
Estado: aceptada

**Decisión.** 125/s en promedio y ráfaga de 125 a 500/s en 1 min, sostenida 5 min.
**Por qué.** Los webhooks los emiten los proveedores; su volumen no depende de los usuarios activos diarios.
