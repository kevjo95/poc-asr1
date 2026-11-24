#!/usr/bin/env python3
"""Genera el informe de un escenario a partir de results/raw/<run>/ (stdlib únicamente)."""
import csv, json, os, sys
from datetime import datetime

run_dir = sys.argv[1].rstrip("/")
meta = json.load(open(f"{run_dir}/meta.json"))
sc, run_id = meta["scenario"], meta["run_id"]
summ = json.load(open(f"results/summaries/{run_id}.json"))
M = summ["metrics"]
env = os.environ.get
P99_MS, ERR = 300.0, 0.001

def v(name, stat):
    m = M.get(name)
    return m["values"].get(stat) if m and "values" in m else None

# --- fases ---
names = sorted({k.split("phase:")[1].rstrip("}") for k in M if k.startswith("lat_phase{phase:")})
order = ["warmup", "burst", "sustained", "return", "steady"]
names.sort(key=lambda n: order.index(n) if n in order else 100 + int(n[1:]) if n[1:].isdigit() else 999)
dur = {"warmup": float(env("WARMUP_S", 300)), "burst": 60.0, "sustained": float(env("HOLD_S", 300)),
       "return": float(env("BACK_S", 120)), "steady": float(env("DURATION_S", 1800))}
step_s = float(env("STEP_S", 60 if sc == "p0" else 120))
rows = []
for n in names:
    p95, p99 = v(f"lat_phase{{phase:{n}}}", "p(95)"), v(f"lat_phase{{phase:{n}}}", "p(99)")
    fail, cnt = v(f"fail_phase{{phase:{n}}}", "rate") or 0.0, v(f"reqs_phase{{phase:{n}}}", "count") or 0
    secs = dur.get(n, step_s)
    target = int(n[1:]) if n[1:].isdigit() else None
    rows.append(dict(n=n, p95=p95, p99=p99, fail=fail, cnt=cnt, rate=cnt / secs if secs else 0, target=target,
                     ok=(p99 is not None and p99 < P99_MS and fail < ERR)))

out = []
w = out.append
w(f"# Informe {sc.upper()} · {run_id}\n")
dropped = v("dropped_iterations", "count") or 0
w(f"- Peticiones: **{int(v('http_reqs','count'))}** · `202`: **{int(v('webhook_accepted','count'))}** · no-202: {int(v('webhook_not_accepted','count') or 0)}")
w(f"- Iteraciones descartadas por k6 (`dropped_iterations`): **{int(dropped)}** "
  + ("✅ el generador no fue el cuello de botella" if dropped == 0 else "⚠️ el generador (o el MS) no sostuvo la tasa pedida"))
w(f"- Código de salida de k6: {meta.get('k6_exit')} (99 = algún umbral no se cumplió)\n")

w("## Latencia y errores por fase\n")
w("| Fase | Tasa lograda | p95 (ms) | p99 (ms) | Errores | ¿Cumple p99<300 y err<0,1 %? |")
w("|---|---|---|---|---|---|")
for r in rows:
    tr = f" (objetivo {r['target']}/s)" if r["target"] else ""
    w(f"| {r['n']} | {r['rate']:.0f}/s{tr} | {r['p95']:.1f} | {r['p99']:.1f} | {r['fail']*100:.3f} % | {'sí' if r['ok'] else 'NO'} |")

if sc == "p0":
    good = [r for r in rows if r["ok"] and r["target"] and r["rate"] >= 0.97 * r["target"]]
    if good:
        best = max(good, key=lambda r: r["target"])
        w(f"\n**Capacidad por réplica (1 réplica fija, HPA apagado): ≈ {best['target']} req/s** (último escalón con p99 < 300 ms y errores < 0,1 %).")
        w(f"Valor objetivo de referencia con el margen del documento (×0,6): ≈ {best['target']*0.6:.0f} req/s por réplica.")
        w(f"Réplicas para 500/s con esa capacidad: {500/best['target']:.1f}; con margen del 40 %: {500/(best['target']*0.6):.1f}.")
    bad = [r for r in rows if not r["ok"]]
    if bad: w(f"Primer escalón fuera de criterio: **{bad[0]['n']}** (p99 {bad[0]['p99']:.0f} ms, errores {bad[0]['fail']*100:.2f} %).")
if sc == "p3":
    bad = [r for r in rows if not r["ok"]]
    w(f"\n**Punto de quiebre:** " + (f"{bad[0]['n']} (p99 {bad[0]['p99']:.0f} ms, errores {bad[0]['fail']*100:.2f} %)" if bad else "no se alcanzó dentro de los escalones ejecutados"))
if sc == "p2":
    s = next((r for r in rows if r["n"] == "sustained"), None)
    if s: w(f"\n**ASR1 · p99 a 500/s sostenidos: {s['p99']:.1f} ms** → {'CUMPLE' if s['p99']<P99_MS else 'NO CUMPLE'} (< 300 ms).")
    tot_fail = sum(r["fail"] * r["cnt"] for r in rows if r["n"] in ("warmup", "burst", "sustained")) / max(1, sum(r["cnt"] for r in rows if r["n"] in ("warmup", "burst", "sustained")))
    w(f"**ASR1 · errores (P2, incluido el escalado): {tot_fail*100:.3f} %** → {'CUMPLE' if tot_fail<ERR else 'NO CUMPLE'} (< 0,1 %).")

# --- réplicas ---
rep = list(csv.DictReader(open(f"{run_dir}/replicas.csv")))
def num(x):
    try: return int(x)
    except Exception: return None
for r in rep:
    r["t"] = int(r["epoch"]) - meta["k6_start"]
    for k in ("spec", "ready", "hpa_current", "hpa_desired", "hpa_cpu_pct"): r[k] = num(r[k])
ready = [r for r in rep if r["ready"] is not None]
w("\n## Réplicas y CPU\n")
if ready:
    r0, rmax = ready[0]["ready"], max(r["ready"] for r in ready)
    w(f"- Réplicas *ready*: inicio **{r0}** → máximo **{rmax}** → final {ready[-1]['ready']}")
    cpu_pct = [r["hpa_cpu_pct"] for r in rep if r["hpa_cpu_pct"] is not None]
    if cpu_pct: w(f"- CPU promedio reportada por el HPA (objetivo 80 % del request): máx **{max(cpu_pct)} %**")
    burst_t = meta.get("burst_offset_s", 0)
    if sc == "p2" and rmax > r0:
        t_desired = next((r["t"] for r in rep if r["t"] >= burst_t and r["hpa_desired"] and r["hpa_desired"] > r0), None)
        t_all = next((r["t"] for r in rep if r["t"] >= burst_t and r["ready"] == rmax), None)
        if t_desired is not None: w(f"- Reacción del HPA (inicio de la ráfaga → decide escalar): **{t_desired-burst_t:.0f} s**")
        if t_all is not None:
            w(f"- **Tiempo de escalado (inicio de la ráfaga → última réplica nueva *ready*): {t_all-burst_t:.0f} s ({(t_all-burst_t)/60:.1f} min)** "
              f"→ {'CUMPLE' if t_all-burst_t <= 180 else 'NO CUMPLE'} (≤ 3 min)")
    elif sc == "p2":
        w(f"- No hubo escalado ({r0} → {rmax}): con esta carga el HPA no necesitó añadir réplicas.")
    w("\nLínea de tiempo (cada ~30 s): `t(s) ready/desired cpu%`\n")
    line = []
    for r in rep[::6]:
        line.append(f"{r['t']}s:{r['ready']}/{r['hpa_desired'] if r['hpa_desired'] is not None else '-'}/{r['hpa_cpu_pct'] if r['hpa_cpu_pct'] is not None else '-'}%")
    w("`" + "  ".join(line) + "`")

# --- arranque de pods ---
def ts(s): return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()  # UTC explícito
pods = json.load(open(f"{run_dir}/pods.json"))["items"]
starts = []
for p in pods:
    created = ts(p["metadata"]["creationTimestamp"])
    if created < meta["k6_start"] - 1: continue          # solo pods creados durante la prueba
    cond = {c["type"]: c for c in p["status"].get("conditions", [])}
    if "Ready" in cond and cond["Ready"]["status"] == "True":
        starts.append(ts(cond["Ready"]["lastTransitionTime"]) - created)
if starts:
    w(f"\n## Arranque de pods nuevos (creación → *Ready*)\n\n- Pods creados durante la prueba: **{len(starts)}** · min {min(starts):.0f} s · promedio {sum(starts)/len(starts):.0f} s · máx **{max(starts):.0f} s**")
    w("- El documento pide < 60 s; si se supera, evaluar CDS o reducir dependencias antes de tocar el autoscaling.")
elif sc == "p2":
    w("\n## Arranque de pods nuevos\n\n- No se crearon pods durante la prueba.")

cpu = list(csv.DictReader(open(f"{run_dir}/cpu.csv")))
if cpu:
    mx = max(int(r["cpu_millicores_max"]) for r in cpu)
    w(f"\n- CPU máxima observada en un pod: **{mx}m** (request 100m, límite 500m).")

w("\n## Conciliación de pérdidas\n")
w("```\n" + open(f"{run_dir}/reconcile.txt").read().strip() + "\n```")
w("\n> Entorno local con recursos reducidos en proporción (ADR 0006): p99 y tiempo de escalado son indicativos, no comparables con producción.")
print("\n".join(out))
