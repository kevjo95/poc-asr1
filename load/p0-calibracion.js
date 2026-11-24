// P0 · Calibración: 1 réplica fija (HPA apagado). Escalones de +STEP/s cada STEP_S segundos hasta que el p99 supere 300 ms.
// Cada escalón es una fase "sNNN" para obtener su p99 y su tasa de error por separado.
import { send, phases, phaseThresholds } from './lib/webhook.js';
import { buildSummary } from './lib/summary.js';

const START = Number(__ENV.START_RATE || 50), STEP = Number(__ENV.STEP || 50);
const STEPS = Number(__ENV.STEPS || 12), STEP_S = Number(__ENV.STEP_S || 60);
const rates = Array.from({ length: STEPS }, (_, i) => START + i * STEP);
const PHASES = rates.map((r) => ({ name: `s${String(r).padStart(4, '0')}`, seconds: STEP_S }));
const phaseOf = phases(PHASES);

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    p0: {
      executor: 'ramping-arrival-rate', startRate: START, timeUnit: '1s',
      preAllocatedVUs: Number(__ENV.PRE_VUS || 300), maxVUs: Number(__ENV.MAX_VUS || 2000),
      // salto instantáneo a cada escalón y sostenido STEP_S segundos
      stages: rates.flatMap((r) => [{ target: r, duration: '1s' }, { target: r, duration: `${STEP_S - 1}s` }]),
    },
  },
  thresholds: {
    ...phaseThresholds(PHASES.map((p) => p.name)),
    // Corte de seguridad: aborta si el sistema ya está claramente saturado (el punto exacto se calcula por escalón).
    webhook_failed: [{ threshold: 'rate<0.2', abortOnFail: true, delayAbortEval: '20s' }],
  },
};
export default function () { send(phaseOf); }
export function handleSummary(data) { return buildSummary('p0', data, PHASES.map((p) => p.name)); }
