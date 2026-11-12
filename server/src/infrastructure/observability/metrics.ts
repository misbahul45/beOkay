export const LATENCY_BUCKETS_MS = [25, 50, 100, 200, 400, 800, 1600, 3200, 6400];

type Histogram = { buckets: number[]; sum: number; count: number };
const requests = new Map<string, number>();
const latency = new Map<string, Histogram>();
const events = new Map<string, number>();
const startedAt = Date.now();

const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

export function normalizePath(path: string): string {
  if (path.startsWith("/s/")) return "/s/:token";
  if (path.startsWith("/api/auth/")) return "/api/auth/*";
  return path.replace(UUID, ":id").replace(/\/\d+(?=\/|$)/g, "/:n").slice(0, 120);
}

export const metrics = {
  observeRequest(method: string, path: string, status: number, durationMs: number) {
    const route = normalizePath(path);
    const klass = `${Math.floor(status / 100)}xx`;
    const key = `${method}|${route}|${klass}`;
    requests.set(key, (requests.get(key) ?? 0) + 1);
    const lk = `${method}|${route}`;
    const h = latency.get(lk) ?? { buckets: LATENCY_BUCKETS_MS.map(() => 0), sum: 0, count: 0 };
    LATENCY_BUCKETS_MS.forEach((b, i) => {
      if (durationMs <= b) h.buckets[i]!++;
    });
    h.sum += durationMs;
    h.count++;
    latency.set(lk, h);
  },

  countEvent(level: string, event: string) {
    if (event === "request") return;
    const key = `${level}|${event}`;
    events.set(key, (events.get(key) ?? 0) + 1);
  },

  snapshot() {
    return { requests: new Map(requests), latency: new Map(latency), events: new Map(events) };
  },

  reset() {
    requests.clear();
    latency.clear();
    events.clear();
  },

  render(gauges: { name: string; help: string; labels?: Record<string, string>; value: number }[] = []) {
    const lines: string[] = [];
    const esc = (v: string) => v.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, " ");
    const lbl = (o: Record<string, string>) => `{${Object.entries(o).map(([k, v]) => `${k}="${esc(v)}"`).join(",")}}`;
    lines.push("# HELP beokay_http_requests_total HTTP requests by method, normalized route and status class.", "# TYPE beokay_http_requests_total counter");
    for (const [k, v] of requests) {
      const [method, route, status] = k.split("|");
      lines.push(`beokay_http_requests_total${lbl({ method: method!, route: route!, status: status! })} ${v}`);
    }
    lines.push("# HELP beokay_http_request_duration_ms Request latency in milliseconds.", "# TYPE beokay_http_request_duration_ms histogram");
    for (const [k, h] of latency) {
      const [method, route] = k.split("|");
      LATENCY_BUCKETS_MS.forEach((b, i) => lines.push(`beokay_http_request_duration_ms_bucket${lbl({ method: method!, route: route!, le: String(b) })} ${h.buckets[i]}`));
      lines.push(`beokay_http_request_duration_ms_bucket${lbl({ method: method!, route: route!, le: "+Inf" })} ${h.count}`);
      lines.push(`beokay_http_request_duration_ms_sum${lbl({ method: method!, route: route! })} ${Math.round(h.sum)}`);
      lines.push(`beokay_http_request_duration_ms_count${lbl({ method: method!, route: route! })} ${h.count}`);
    }
    lines.push("# HELP beokay_log_events_total Structured log events by level and name.", "# TYPE beokay_log_events_total counter");
    for (const [k, v] of events) {
      const [level, event] = k.split("|");
      lines.push(`beokay_log_events_total${lbl({ level: level!, event: event! })} ${v}`);
    }
    const seen = new Set<string>();
    for (const g of gauges) {
      if (!seen.has(g.name)) {
        lines.push(`# HELP ${g.name} ${g.help}`, `# TYPE ${g.name} gauge`);
        seen.add(g.name);
      }
      lines.push(`${g.name}${g.labels ? lbl(g.labels) : ""} ${g.value}`);
    }
    lines.push("# HELP beokay_process_uptime_seconds Seconds since the API process started.", "# TYPE beokay_process_uptime_seconds gauge", `beokay_process_uptime_seconds ${Math.round((Date.now() - startedAt) / 1000)}`);
    lines.push("# HELP beokay_process_resident_memory_bytes Resident memory.", "# TYPE beokay_process_resident_memory_bytes gauge", `beokay_process_resident_memory_bytes ${process.memoryUsage().rss}`);
    return lines.join("\n") + "\n";
  },
};

export function p95FromBuckets(h: { buckets: number[]; count: number }): number | null {
  if (h.count === 0) return null;
  const target = h.count * 0.95;
  for (let i = 0; i < LATENCY_BUCKETS_MS.length; i++) if (h.buckets[i]! >= target) return LATENCY_BUCKETS_MS[i]!;
  return Number.POSITIVE_INFINITY;
}

export function parsePrometheus(text: string) {
  const out: { name: string; labels: Record<string, string>; value: number }[] = [];
  for (const line of text.split("\n")) {
    if (!line || line.startsWith("#")) continue;
    const m = line.match(/^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{(.*)\})? (\S+)$/);
    if (!m) continue;
    const labels: Record<string, string> = {};
    for (const p of (m[3] ?? "").matchAll(/(\w+)="((?:[^"\\]|\\.)*)"/g)) labels[p[1]!] = p[2]!;
    out.push({ name: m[1]!, labels, value: Number(m[4]) });
  }
  return out;
}
