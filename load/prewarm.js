// Pre-calentamiento: tráfico suave y corto para que la JVM compile (JIT) y abra conexiones antes de medir.
// No es un escenario de medición; su tráfico se purga de la cola antes de la prueba.
import { send, phases } from './lib/webhook.js';
const RATE = Number(__ENV.PREWARM_RATE || 40), DUR = Number(__ENV.PREWARM_S || 90);
const phaseOf = phases([{ name: 'prewarm', seconds: DUR }]);
export const options = {
  scenarios: { prewarm: { executor: 'constant-arrival-rate', rate: RATE, timeUnit: '1s', duration: `${DUR}s`, preAllocatedVUs: 50, maxVUs: 200 } },
};
export default function () { send(phaseOf); }
