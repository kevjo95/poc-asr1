// P1 · Base: 125/s sostenidos (30 min por defecto), con el mínimo de réplicas y HPA activo.
import { send, phases, phaseThresholds } from './lib/webhook.js';
import { buildSummary } from './lib/summary.js';

const RATE = Number(__ENV.BASE_RATE || 125), DUR = Number(__ENV.DURATION_S || 1800);
const PHASES = [{ name: 'steady', seconds: DUR }];
const phaseOf = phases(PHASES);

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    p1: { executor: 'constant-arrival-rate', rate: RATE, timeUnit: '1s', duration: `${DUR}s`,
          preAllocatedVUs: Number(__ENV.PRE_VUS || 200), maxVUs: Number(__ENV.MAX_VUS || 1000) },
  },
  thresholds: {
    ...phaseThresholds(PHASES.map((p) => p.name)),
    'lat_phase{phase:steady}': ['p(99)<300'],
    'fail_phase{phase:steady}': ['rate<0.001'],
    dropped_iterations: ['count==0'],
  },
};
export default function () { send(phaseOf); }
export function handleSummary(data) { return buildSummary('p1', data, ['steady']); }
