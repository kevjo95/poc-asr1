# AS-IS → TO-BE de la configuración del MS de ingesta

**Idea.** La configuración observada en un servicio comparable de producción (AS-IS) es la **línea base**. El MS de ingesta recibe ráfagas (125 → 500 req/s en 1 min)
que ese servicio nunca ha visto, así que su perfil (TO-BE) puede y debe diferir. Cada cambio se admite solo si hay una medición que lo justifique;
se reporta primero el resultado con la línea base y después con el perfil propio, con su costo.

Estado: **Medido** (evidencia ejecutada) · **Hipótesis** (por probar) · **Decisión** (ya aplicada, con su ADR).

| Parámetro | AS-IS observado | TO-BE propuesto | Evidencia / por qué | Estado |
|---|---|---|---|---|
| CPU request / límite | 200m / 2000m | 100m / **por definir (≥ 2000m)** | La JVM ve 1 CPU con límite ≤ 1000m (`system_cpu_count=1`); con 2000m ve 2 | Hipótesis (E3, E4) |
| Hilos de la aplicación | Valores por defecto de Spring (Tomcat 200, sin virtual threads) | Por decidir: virtual threads o por defecto | A 500 req/s la concurrencia ≈ 3 (ley de Little), no limita; lo limita el CPU | Hipótesis (E4, E5) |
| Log por petición | No medido | Nivel WARN en la ruta caliente (INFO produce ~1 línea JSON por petición) | 76.904 eventos INFO en un pod | Hipótesis (E1, E2) |
| Memoria | 3096 MiB (heap 2 GiB) | 1 GiB (heap 512 MiB) en local; en AWS, proporcional al heap | 768 MiB → `OOMKilled` | Medido (P0-1) |
| *Liveness* | No medido | `timeoutSeconds: 3`, `failureThreshold: 6` | Un pod saturado se reiniciaba y empeoraba la caída | Medido (P0-2) |
| HPA réplicas | 4 – 8 | 4 – 8 (a validar si 8 alcanza) | Pendiente de P2 con el perfil final | Hipótesis |
| HPA objetivo de CPU | 80 % del request | 80 % (a validar; posible 60 % si degrada de golpe) | El servicio degrada en cliff: 0 % → 9 % → 88 % de errores en dos escalones | Hipótesis |
| Escalado hacia arriba | 0 s, 4 pods por 90 s | igual | — | Sin cambio |
| Escalado hacia abajo | 300 s, 4 pods por 90 s | igual | — | Sin cambio |
| Precalentamiento / arranque | No aplica | Sondas de *startup*; considerar CDS/AppCDS si el arranque supera 60 s | Pods nuevos *Ready* en 9–11 s en local; el arranque en frío consume CPU > 150 % | Medido |

## Protocolo de comparación (obligatorio en cada cambio TO-BE)
1. Ejecutar el escenario con la **línea base AS-IS** y registrar el resultado.
2. Aplicar **un** cambio TO-BE, repetir y registrar el delta.
3. Anotar el costo del cambio (CPU reservado, réplicas, complejidad) y si el HPA sigue escalando de forma horizontal.
4. Registrar la decisión en un ADR y en `docs/cambios-al-documento.md`.

## Cómo entra al documento de la clase
Sección propuesta: «Configuración AS-IS observada y TO-BE recomendada para el MS de ingesta», con esta tabla como resultado de la PoC.
Es una contribución adicional al ASR1: además de validar la hipótesis, la PoC indica qué debe cambiar respecto del servicio de referencia para sostenerla.
