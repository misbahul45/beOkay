import { z } from "zod";

/**
 * Klien inferensi Modal. Menerima hanya https://*.modal.run, memakai bearer dari env, batas waktu, satu coba-ulang
 * untuk 5xx/jaringan, circuit breaker (3 gagal beruntun → buka 60 dtk), dan memvalidasi balasan. Hanya byte gambar yang
 * dikirim: tidak ada identitas pengguna. Kegagalan tidak pernah dilempar ke jalur pengguna; hasilnya berupa kode.
 */
const response = z.object({
  modelKey: z.string().min(1).max(80),
  modelVersion: z.string().min(1).max(80),
  artifactSha256: z.string().regex(/^[0-9a-f]{64}$/),
  predictions: z.array(z.object({ label: z.string().min(1).max(80), probability: z.number().min(0).max(1) })).min(1).max(5),
  latencyMs: z.number().min(0).optional(),
});
export type ModalPrediction = z.infer<typeof response>;
export type ModalResult = { ok: true; data: ModalPrediction; latencyMs: number } | { ok: false; code: "NOT_CONFIGURED" | "TIMEOUT" | "UNAVAILABLE" | "INVALID_RESPONSE" | "CIRCUIT_OPEN"; latencyMs: number };

export function allowedModalUrl(raw: string | undefined): URL | null {
  if (!raw) return null;
  try {
    const u = new URL(raw);
    return u.protocol === "https:" && !u.username && !u.password && (u.hostname === "modal.run" || u.hostname.endsWith(".modal.run")) ? u : null;
  } catch {
    return null;
  }
}

export function createModalClient(
  config: { url: string | undefined; token: string | undefined; timeoutMs?: number; failureThreshold?: number; openMs?: number },
  deps: { fetchImpl?: typeof fetch; now?: () => number } = {},
) {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const now = deps.now ?? Date.now;
  const url = allowedModalUrl(config.url);
  const timeoutMs = config.timeoutMs ?? 15_000;
  const threshold = config.failureThreshold ?? 3;
  const openMs = config.openMs ?? 60_000;
  let failures = 0;
  let openedAt = 0;

  const attempt = async (bytes: Uint8Array, topK: number): Promise<{ status: number; body: unknown } | "TIMEOUT" | "NETWORK"> => {
    try {
      const res = await fetchImpl(url!, {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(timeoutMs),
        headers: { authorization: `Bearer ${config.token}`, "content-type": "application/json" },
        body: JSON.stringify({ imageBase64: Buffer.from(bytes).toString("base64"), topK }),
      });
      const text = await res.text();
      if (text.length > 100_000) return { status: 502, body: null };
      let body: unknown = null;
      try {
        body = text ? JSON.parse(text) : null;
      } catch {
        body = null;
      }
      return { status: res.status, body };
    } catch (e) {
      return e instanceof Error && (e.name === "TimeoutError" || e.name === "AbortError") ? "TIMEOUT" : "NETWORK";
    }
  };

  return {
    configured: Boolean(url && config.token),
    get circuitOpen() {
      return failures >= threshold && now() - openedAt < openMs;
    },
    async predict(bytes: Uint8Array, topK = 3): Promise<ModalResult> {
      const t0 = now();
      if (!url || !config.token) return { ok: false, code: "NOT_CONFIGURED", latencyMs: 0 };
      if (failures >= threshold) {
        if (now() - openedAt < openMs) return { ok: false, code: "CIRCUIT_OPEN", latencyMs: 0 };
        failures = threshold - 1; // setengah-terbuka: satu percobaan
      }
      const fail = (code: "TIMEOUT" | "UNAVAILABLE" | "INVALID_RESPONSE"): ModalResult => {
        failures++;
        if (failures >= threshold) openedAt = now();
        return { ok: false, code, latencyMs: now() - t0 };
      };
      let r = await attempt(bytes, topK);
      if (r === "NETWORK" || (typeof r === "object" && r.status >= 500)) r = await attempt(bytes, topK); // satu coba-ulang
      if (r === "TIMEOUT") return fail("TIMEOUT");
      if (r === "NETWORK") return fail("UNAVAILABLE");
      if (r.status === 401 || r.status === 403 || r.status >= 500) return fail("UNAVAILABLE");
      if (r.status !== 200) return fail("INVALID_RESPONSE");
      const parsed = response.safeParse(r.body);
      if (!parsed.success) return fail("INVALID_RESPONSE");
      const sum = parsed.data.predictions.reduce((s, p) => s + p.probability, 0);
      if (sum > 1.001) return fail("INVALID_RESPONSE");
      failures = 0;
      return { ok: true, data: parsed.data, latencyMs: now() - t0 };
    },
  };
}
export type ModalClient = ReturnType<typeof createModalClient>;
