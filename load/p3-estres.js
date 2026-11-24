// P3 · Estrés: rampa por escalones desde 500/s con HPA activo (máx 8 réplicas), hasta p99 > 300 ms o errores > 0,1 %.
import { send, phases, phaseThresholds } from './lib/webhook.js';
import { buildSummary } from './lib/summary.js';

const START = Number(__ENV.START_RATE || 500), STEP = Number(__ENV.STEP || 100);
const STEPS = Number(__ENV.STEPS || 8), STEP_S = Number(__ENV.STEP_S || 120);
const rates = Array.from({ length: STEPS }, (_, i) => START + i * STEP);
const PHASES = rates.map((r) => ({ name: `s${String(r).padStart(4, '0')}`, seconds: STEP_S }));
const phaseOf = phases(PHASES);

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    p3: {
      executor: 'ramping-arrival-rate', startRate: START, timeUnit: '1s',
      preAllocatedVUs: Number(__ENV.PRE_VUS || 400), maxVUs: Number(__ENV.MAX_VUS || 3000),
      stages: rates.flatMap((r) => [{ target: r, duration: '10s' }, { target: r, duration: `${STEP_S - 10}s` }]),
    },
  },
  thresholds: {
    ...phaseThresholds(PHASES.map((p) => p.name)), webhook_failed: [{ threshold: 'rate<0.2', abortOnFail: true, delayAbortEval: '30s' }] },
};
export default function () { send(phaseOf); }
export function handleSummary(data) { return buildSummary('p3', data, PHASES.map((p) => p.name)); }
