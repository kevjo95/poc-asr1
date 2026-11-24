#!/usr/bin/env python3
"""Dashboard de monitoreo de la PoC (solo lectura, sin dependencias salvo boto3).

Lee del clúster (API de Kubernetes vía kubectl), de las métricas Prometheus de cada pod (por el proxy del API server)
y de LocalStack (SQS, DynamoDB, Lambda). Sirve una página en http://localhost:8765.
Uso: KUBECONFIG=... python3 scripts/dashboard/server.py
"""
import collections, http.server, json, math, os, re, socketserver, subprocess, threading, time
from datetime import datetime, timezone
import boto3

PORT = int(os.environ.get("PORT", 8765))
NS = os.environ.get("NS", "default")
APP = os.environ.get("APP", "ingest-ms")
PERIOD = float(os.environ.get("PERIOD", 2))
PREFIX = os.environ.get("PREFIX", "poc-asr1")
P99_LIMIT_MS, ERR_LIMIT, HPA_TARGET = 300.0, 0.001, 80
HIST = collections.deque(maxlen=int(os.environ.get("HISTORY", 450)))      # ~15 min a 2 s
EVENTS = collections.deque(maxlen=60)
LOCK = threading.Lock()
STATE = {"loaded": False}
AWS_MODE = bool(os.environ.get("USE_AWS"))
SENT = {"total": 0.0}   # 202 aceptados desde que arrancó el dashboard (suma de deltas de los contadores de los pods)

if not os.environ.get("USE_AWS"):
    os.environ.setdefault("AWS_ACCESS_KEY_ID", "test"); os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")
ENDPOINT = None if os.environ.get("USE_AWS") else os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
kw = dict(region_name="us-east-1", endpoint_url=ENDPOINT)
sqs, ddb, lam = boto3.client("sqs", **kw), boto3.client("dynamodb", **kw), boto3.client("lambda", **kw)


def kraw(path):
    r = subprocess.run(["kubectl", "get", "--raw", path], capture_output=True, text=True, timeout=6)
    return r.stdout if r.returncode == 0 else ""


def cpu_m(q):
    if q.endswith("n"): return float(q[:-1]) / 1e6
    if q.endswith("u"): return float(q[:-1]) / 1e3
    if q.endswith("m"): return float(q[:-1])
    return float(q) * 1000


LINE = re.compile(r'^([a-zA-Z_:][\w:]*)(\{.*\})?\s+(\S+)$')   # las etiquetas pueden contener llaves: uri="/webhooks/{source}"


def parse_prom(text):
    """Devuelve (count_ok, count_err, buckets{le:cuenta}) de /webhooks y del SendMessage a SQS."""
    out = {"w_ok": 0.0, "w_err": 0.0, "w_b": collections.defaultdict(float), "s_cnt": 0.0, "s_b": collections.defaultdict(float)}
    for ln in text.splitlines():
        if ln.startswith("#"): continue
        m = LINE.match(ln)
        if not m: continue
        name, labels, val = m.group(1), m.group(2) or "", m.group(3)
        try: val = float(val)
        except ValueError: continue
        if name.startswith("http_server_requests_seconds") and "/webhooks/" in labels:
            if name.endswith("_count"):
                st = re.search(r'status="(\d+)"', labels)
                if st and st.group(1) == "202": out["w_ok"] += val
                else: out["w_err"] += val
            elif name.endswith("_bucket"):
                le = re.search(r'le="([^"]+)"', labels)
                if le: out["w_b"][le.group(1)] += val
        elif name.startswith("ingest_sqs_send_latency_seconds"):
            if name.endswith("_count"): out["s_cnt"] += val
            elif name.endswith("_bucket"):
                le = re.search(r'le="([^"]+)"', labels)
                if le: out["s_b"][le.group(1)] += val
    return out


def pctl(delta_buckets, q=0.99):
    """p99 (ms) estimado por interpolación lineal sobre buckets acumulados (delta entre dos lecturas)."""
    items = sorted(((math.inf if k == "+Inf" else float(k), v) for k, v in delta_buckets.items()))
    if not items or items[-1][1] <= 0: return None
    total, target, prev_le, prev_c = items[-1][1], q * items[-1][1], 0.0, 0.0
    for le, c in items:
        if c >= target:
            if le == math.inf: return prev_le * 1000
            frac = (target - prev_c) / (c - prev_c) if c > prev_c else 1
            return (prev_le + (le - prev_le) * frac) * 1000
        prev_le, prev_c = le, c
    return None


def add(msg, level="info"):
    EVENTS.appendleft({"t": datetime.now().strftime("%H:%M:%S"), "msg": msg, "level": level})


PREV_POD, PREV_T, LAST = {}, None, {"desired": None, "ready": None, "dlq": 0, "lambda": None, "pods": set()}


SCEN = {
    "p0-calibracion": ("P0 · Calibración", "1 réplica fija, HPA apagado. Sube +50 req/s cada 60 s hasta que el p99 supere 300 ms: mide la capacidad de un pod."),
    "p1-base": ("P1 · Carga base", "125 req/s constantes con HPA activo (4–8). Debe cumplir p99 < 300 ms y errores < 0,1 % sin escalar."),
    "p2-rafaga": ("P2 · Ráfaga de nómina (ASR1)", "125 → 500 req/s en 1 min, sostenido 5 min, con HPA activo. Mide p99, errores y tiempo de escalado."),
    "p3-estres": ("P3 · Estrés", "Desde 500 req/s, +100 cada 2 min hasta el punto de quiebre del sistema con HPA activo."),
}


def scenario():
    """Detecta el escenario en curso por el proceso de k6 (el dashboard no depende de run-scenario.sh)."""
    try:  # marcador escrito por run-scenario.sh (el generador puede estar dentro del clúster)
        m = json.load(open("results/raw/.current-scenario"))
        for key, (title, desc) in SCEN.items():
            if key.startswith(m["scenario"] + "-"):
                secs = int(time.time() - m["start"])
                extra = f"escalón actual ≈ {50 + 50 * min(11, secs // 60)} req/s" if m["scenario"] == "p0" else None
                return {"title": title, "desc": desc, "elapsed": secs, "extra": extra}
    except Exception:
        pass
    try:
        out = subprocess.run(["ps", "-axo", "etime=,command="], capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return None
    for ln in out.splitlines():
        if "k6" in ln and " run " in ln:
            for key, (title, desc) in SCEN.items():
                if f"load/{key}.js" in ln:
                    et = ln.split()[0]; parts = [int(x) for x in re.split(r"[-:]", et)]
                    secs = 0
                    for x in parts: secs = secs * 60 + x if len(parts) <= 3 else secs
                    if len(parts) == 4: secs = ((parts[0] * 24 + parts[1]) * 60 + parts[2]) * 60 + parts[3]
                    extra = None
                    if key == "p0-calibracion":
                        extra = f"escalón actual ≈ {50 + 50 * min(11, secs // 60)} req/s"
                    return {"title": title, "desc": desc, "elapsed": secs, "extra": extra}
    return None


def collect():
    global PREV_POD, PREV_T
    now = time.time()
    sel = f"labelSelector=app.kubernetes.io/name%3D{APP}"
    pods_j = json.loads(kraw(f"/api/v1/namespaces/{NS}/pods?{sel}") or '{"items":[]}')
    met_j = json.loads(kraw(f"/apis/metrics.k8s.io/v1beta1/namespaces/{NS}/pods?{sel}") or '{"items":[]}')
    hpa_j = json.loads(kraw(f"/apis/autoscaling/v2/namespaces/{NS}/horizontalpodautoscalers/{APP}") or '{}')
    cpu = {i["metadata"]["name"]: cpu_m(i["containers"][0]["usage"]["cpu"]) for i in met_j.get("items", []) if i.get("containers")}

    pods, cur_pod = [], {}
    agg_cnt_ok = agg_cnt_err = 0.0
    agg_b, agg_sb = collections.defaultdict(float), collections.defaultdict(float)
    dt = (now - PREV_T) if PREV_T else None
    for p in pods_j.get("items", []):
        name = p["metadata"]["name"]
        ready = any(c["type"] == "Ready" and c["status"] == "True" for c in p["status"].get("conditions", []))
        terminating = "deletionTimestamp" in p["metadata"]
        row = {"name": name[-5:], "node": p["spec"].get("nodeName", "-").replace("poc-asr1-", ""),
               "state": "Terminating" if terminating else ("Ready" if ready else p["status"].get("phase", "?")),
               "age": int(now - datetime.fromisoformat(p["metadata"]["creationTimestamp"].replace("Z", "+00:00")).timestamp()),
               "cpu": round(cpu.get(name, 0), 1), "rps": 0.0, "p99": None, "ready_s": None}
        if ready:
            rt = next((c.get("lastTransitionTime") for c in p["status"].get("conditions", []) if c["type"] == "Ready"), None)
            if rt: row["ready_s"] = int(datetime.fromisoformat(rt.replace("Z", "+00:00")).timestamp() - datetime.fromisoformat(p["metadata"]["creationTimestamp"].replace("Z", "+00:00")).timestamp())
        if ready and not terminating:
            prom = parse_prom(kraw(f"/api/v1/namespaces/{NS}/pods/{name}:8080/proxy/actuator/prometheus"))
            cur_pod[name] = prom
            prev = PREV_POD.get(name)
            if prev and dt:
                d_ok = max(0.0, prom["w_ok"] - prev["w_ok"]) if prom["w_ok"] >= prev["w_ok"] else prom["w_ok"]
                d_er = max(0.0, prom["w_err"] - prev["w_err"]) if prom["w_err"] >= prev["w_err"] else prom["w_err"]
                row["rps"] = round((d_ok + d_er) / dt, 1)
                db = {k: max(0.0, v - prev["w_b"].get(k, 0.0)) for k, v in prom["w_b"].items()}
                dsb = {k: max(0.0, v - prev["s_b"].get(k, 0.0)) for k, v in prom["s_b"].items()}
                row["p99"] = None if row["rps"] == 0 else (round(pctl(db), 1) if pctl(db) is not None else None)
                agg_cnt_ok += d_ok; agg_cnt_err += d_er; SENT["total"] += d_ok
                for k, v in db.items(): agg_b[k] += v
                for k, v in dsb.items(): agg_sb[k] += v
        pods.append(row)
    PREV_POD, PREV_T = cur_pod, now
    pods.sort(key=lambda r: (r["state"] != "Ready", -r["age"]))

    nodes_j = json.loads(kraw("/api/v1/nodes") or '{"items":[]}')
    nodes = []
    for n in nodes_j.get("items", []):
        conds = {c["type"]: c for c in n["status"].get("conditions", [])}
        nready = conds.get("Ready", {}).get("status") == "True"
        t0 = datetime.fromisoformat(n["metadata"]["creationTimestamp"].replace("Z", "+00:00")).timestamp()
        tr = conds.get("Ready", {}).get("lastTransitionTime")
        nodes.append({"name": n["metadata"]["name"].replace(".ec2.internal", "").replace(".compute.internal", "").replace("poc-asr1-", "")[-22:],
                      "role": n["metadata"].get("labels", {}).get("role", "control" if "control-plane" in str(n["metadata"].get("labels", {})) else "-"),
                      "type": n["metadata"].get("labels", {}).get("node.kubernetes.io/instance-type", "-"), "ready": nready, "age": int(now - t0),
                      "ready_s": int(datetime.fromisoformat(tr.replace("Z", "+00:00")).timestamp() - t0) if (tr and nready) else None})
    pending = sum(1 for r in pods if r["state"] == "Pending")
    total = agg_cnt_ok + agg_cnt_err
    rps = round(total / dt, 1) if dt else 0.0
    p99 = pctl(agg_b) if total > 0 else None
    sq99 = pctl(agg_sb) if total > 0 else None
    err = (agg_cnt_err / total) if total > 0 else 0.0

    spec, st = hpa_j.get("spec", {}), hpa_j.get("status", {})
    cm = (st.get("currentMetrics") or [{}])[0].get("resource", {}).get("current", {})
    hpa = {"enabled": bool(hpa_j), "min": spec.get("minReplicas"), "max": spec.get("maxReplicas"),
           "current": st.get("currentReplicas"), "desired": st.get("desiredReplicas"), "cpu_pct": cm.get("averageUtilization")}
    ready_n = sum(1 for r in pods if r["state"] == "Ready")

    def qa(url):
        a = sqs.get_queue_attributes(QueueUrl=url, AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"])["Attributes"]
        return int(a["ApproximateNumberOfMessages"]), int(a["ApproximateNumberOfMessagesNotVisible"])
    q = sqs.get_queue_url(QueueName=f"{PREFIX}-ingest")["QueueUrl"]; dq = sqs.get_queue_url(QueueName=f"{PREFIX}-ingest-dlq")["QueueUrl"]
    qv, qf = qa(q); dv, df = qa(dq)
    try: items = None if AWS_MODE else ddb.describe_table(TableName=f"{PREFIX}-idempotency")["Table"]["ItemCount"]  # en DynamoDB real se actualiza cada ~6 h
    except Exception: items = None
    try: lstate = lam.list_event_source_mappings(FunctionName=f"{PREFIX}-reconciler")["EventSourceMappings"][0]["State"]
    except Exception: lstate = "?"

    # eventos legibles para el video
    if hpa["desired"] is not None and LAST["desired"] not in (None, 0) and hpa["desired"] != LAST["desired"]:
        cpu_txt = f"CPU {hpa['cpu_pct']} % vs objetivo {HPA_TARGET} %" if hpa["cpu_pct"] is not None else "sin métrica aún"
        add(f"HPA decide {LAST['desired']} → {hpa['desired']} réplicas ({cpu_txt})", "scale")
    if LAST["ready"] is not None and ready_n != LAST["ready"]:
        add(f"Réplicas listas: {LAST['ready']} → {ready_n}", "scale")
    cur_names = {r["name"] for r in pods}
    for n in cur_names - LAST["pods"]:
        if LAST["pods"]: add(f"Pod nuevo {n} creado", "info")
    if dv + df > 0 and not LAST["dlq"]: add(f"DLQ con {dv + df} mensajes", "bad")
    if lstate != LAST["lambda"] and LAST["lambda"] is not None: add(f"Lambda de conciliación: {lstate}", "info")
    if LAST.get("nodes") is not None and len(nodes) != LAST["nodes"]:
        add(f"Nodos del clúster: {LAST['nodes']} → {len(nodes)}", "scale")
    if LAST.get("pending") is not None and pending > LAST["pending"]:
        add(f"{pending} pod(s) en Pending (esperan capacidad)", "bad")
    LAST["nodes"], LAST["pending"] = len(nodes), pending
    LAST.update(desired=hpa["desired"], ready=ready_n, dlq=dv + df, pods=cur_names); LAST["lambda"] = lstate

    snap = {"t": int(now), "rps": rps, "p99": None if p99 is None else round(p99, 1), "sqs_p99": None if sq99 is None else round(sq99, 1),
            "err": round(err * 100, 3), "ready": ready_n, "hpa": hpa, "queue": qv + qf, "queue_visible": qv, "queue_inflight": qf,
            "dlq": dv + df, "items": items, "aws": AWS_MODE, "sent_total": int(SENT["total"]),
            "nodes": nodes, "pending": pending, "lambda": lstate, "pods": pods,
            "scenario": scenario(), "limits": {"p99_ms": P99_LIMIT_MS, "err_pct": ERR_LIMIT * 100, "hpa_target": HPA_TARGET}}
    with LOCK:
        STATE.update(snap); STATE["loaded"] = True
        HIST.append({k: snap[k] for k in ("t", "rps", "p99", "sqs_p99", "err", "ready", "queue", "dlq")} | {"nodes": len(nodes), "pending": pending, "desired": hpa["desired"], "cpu_pct": hpa["cpu_pct"]})


def loop():
    add("Dashboard iniciado", "info")
    while True:
        t0 = time.time()
        try: collect()
        except Exception as e:  # noqa: BLE001 - el dashboard no debe caerse
            with LOCK: STATE["error"] = f"{type(e).__name__}: {e}"
        time.sleep(max(0.2, PERIOD - (time.time() - t0)))


class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith("/api/state"):
            with LOCK: body = json.dumps({"state": STATE, "history": list(HIST), "events": list(EVENTS)}).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Cache-Control", "no-store")
            self.end_headers(); self.wfile.write(body); return
        if self.path in ("/", "/index.html"):
            body = open(os.path.join(os.path.dirname(__file__), "index.html"), "rb").read()
            self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8"); self.end_headers(); self.wfile.write(body); return
        self.send_error(404)


if __name__ == "__main__":
    threading.Thread(target=loop, daemon=True).start()
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), H) as srv:
        print(f"Dashboard en http://localhost:{PORT}  (Ctrl+C para salir)")
        srv.serve_forever()
