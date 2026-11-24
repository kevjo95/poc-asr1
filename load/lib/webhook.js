// Generador de webhooks sintéticos firmados con HMAC-SHA256 (contrato de la PoC, §6.1).
import http from 'k6/http';
import { check } from 'k6';
import { hmac } from 'k6/crypto';
import exec from 'k6/execution';
import { Counter, Rate, Trend } from 'k6/metrics';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const SECRET = __ENV.HMAC_SECRET || 'poc-local-secret';
const RUN_ID = __ENV.RUN_ID || `r${Date.now()}`;
const SOURCES = ['argyle', 'central-payments'];
const PAD = 'x'.repeat(Number(__ENV.PAD_BYTES || 1000));   // cuerpo de ~1-2 KB, como el volumen real

export const accepted = new Counter('webhook_accepted');         // 202 recibidos (para conciliar)
export const rejected = new Counter('webhook_not_accepted');     // cualquier otra respuesta
export const failAll = new Rate('webhook_failed');
// Métricas por ventana/fase: permiten p99 de la fase sostenida y no el acumulado de toda la corrida.
export const latPhase = new Trend('lat_phase', true);
export const failPhase = new Rate('fail_phase');
export const reqsPhase = new Counter('reqs_phase');   // peticiones por fase (tasa lograda)

// k6 solo reporta submétricas con umbral declarado: se registran todas las fases con umbrales triviales.
export function phaseThresholds(names) {
  const t = {};
  for (const n of names) {
    t[`lat_phase{phase:${n}}`] = ['max>=0'];
    t[`fail_phase{phase:${n}}`] = ['rate>=0'];
    t[`reqs_phase{phase:${n}}`] = ['count>=0'];
  }
  return t;
}

export function send(phaseOf) {
  const i = exec.scenario.iterationInTest;
  const eventId = `${RUN_ID}-${i}`;
  const source = SOURCES[i % 2];
  const body = JSON.stringify({
    eventId,
    type: 'deposit.settled',
    occurredAt: '2026-12-01T13:00:00Z',
    accountId: `acc_${i % 100000}`,
    amount: { value: 1250.75, currency: 'USD' },
    metadata: { employer: PAD, payPeriod: '2026-11-16/2026-11-30' },
  });
  const phase = phaseOf(exec.instance.currentTestRunDuration);
  const res = http.post(`${BASE_URL}/webhooks/${source}`, body, {
    headers: {
      'Content-Type': 'application/json',
      'X-Event-Id': eventId,
      'X-Signature': `sha256=${hmac('sha256', SECRET, body, 'hex')}`,
    },
    timeout: '5s',
    tags: { phase },
  });
  const ok = res.status === 202;
  check(res, { 'status 202': () => ok });
  (ok ? accepted : rejected).add(1);
  failAll.add(!ok);
  latPhase.add(res.timings.duration, { phase });
  failPhase.add(!ok, { phase });
  reqsPhase.add(1, { phase });
}

// Convierte una lista [{name, seconds}] en una función elapsedMs -> nombre de fase.
export function phases(list) {
  const ends = [];
  let acc = 0;
  for (const p of list) { acc += p.seconds * 1000; ends.push([acc, p.name]); }
  return (ms) => { for (const [end, name] of ends) if (ms < end) return name; return ends[ends.length - 1][1]; };
}
