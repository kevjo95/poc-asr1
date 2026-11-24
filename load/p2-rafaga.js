// P2 · Ráfaga (ASR1): 125 -> 500/s en 1 min, sostenido 5 min. Con HPA activo, desde el mínimo de réplicas.
import { send, phases, phaseThresholds } from './lib/webhook.js';
import { buildSummary } from './lib/summary.js';

const BASE = Number(__ENV.BASE_RATE || 125), PEAK = Number(__ENV.PEAK_RATE || 500);
const W = Number(__ENV.WARMUP_S || 300), HOLD = Number(__ENV.HOLD_S || 300), BACK = Number(__ENV.BACK_S || 120);
const PHASES = [
  { name: 'warmup', seconds: W }, { name: 'burst', seconds: 60 },
  { name: 'sustained', seconds: HOLD }, { name: 'return', seconds: BACK },
];
const phaseOf = phases(PHASES);

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    p2: {
      executor: 'ramping-arrival-rate', startRate: BASE, timeUnit: '1s',
      preAllocatedVUs: Number(__ENV.PRE_VUS || 300), maxVUs: Number(__ENV.MAX_VUS || 1500),
      stages: [
        { target: BASE, duration: `${W}s` }, { target: PEAK, duration: '60s' },
        { target: PEAK, duration: `${HOLD}s` }, { target: BASE, duration: `${BACK}s` },
      ],
    },
  },
  thresholds: {
    ...phaseThresholds(PHASES.map((p) => p.name)),
    'lat_phase{phase:sustained}': ['p(99)<300'],        // ASR1: p99 a 500/s sostenidos
    'fail_phase{phase:warmup}': ['rate<0.001'],
    'fail_phase{phase:burst}': ['rate<0.001'],           // errores incluido el periodo de escalado
    'fail_phase{phase:sustained}': ['rate<0.001'],
    dropped_iterations: ['count==0'],                    // el generador no debe ser el cuello de botella
  },
};
export default function () { send(phaseOf); }
export function handleSummary(data) { return buildSummary('p2', data, PHASES.map((p) => p.name)); }
