// Resumen: JSON completo para el análisis y un texto corto con las medidas del ASR1.
function val(data, name, stat) {
  const m = data.metrics[name];
  return m && m.values ? m.values[stat] : undefined;
}
export function buildSummary(scenario, data, phaseNames) {
  const run = __ENV.RUN_ID || 'run';
  const lines = [`== ${scenario} · ${run} ==`];
  lines.push(`peticiones=${val(data, 'http_reqs', 'count')}  202=${val(data, 'webhook_accepted', 'count')}  no-202=${val(data, 'webhook_not_accepted', 'count') || 0}`);
  lines.push(`dropped_iterations=${val(data, 'dropped_iterations', 'count') || 0}  (debe ser 0: si no, el generador es el cuello de botella)`);
  for (const ph of phaseNames) {
    const key = `lat_phase{phase:${ph}}`;
    const p99 = val(data, key, 'p(99)');
    const p95 = val(data, key, 'p(95)');
    const fail = val(data, `fail_phase{phase:${ph}}`, 'rate');
    const n = val(data, `reqs_phase{phase:${ph}}`, 'count');
    if (p99 !== undefined) lines.push(`fase ${ph.padEnd(10)} p95=${p95.toFixed(1)}ms  p99=${p99.toFixed(1)}ms  errores=${((fail || 0) * 100).toFixed(3)}%  n=${n}`);
  }
  const out = {};
  out[`results/summaries/${run}.json`] = JSON.stringify(data, null, 2);
  out.stdout = lines.join('\n') + '\n';
  return out;
}
