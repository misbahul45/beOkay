/**
 * Kandidat pangan dari sumber luar. Bukan catatan: tidak disimpan sampai pengguna menyimpannya
 * sebagai makanan pribadi (status "estimated"). Nilai yang tidak ada / tidak masuk akal = null, bukan 0.
 */
export type Per100g = {
  calories: number | null;
  carbohydrates: number | null;
  protein: number | null;
  fat: number | null;
  fiber: number | null;
};

export type FoodCandidate = {
  externalId: string;
  name: string;
  brand: string | null;
  source: "Open Food Facts" | "USDA FoodData Central" | "Label kemasan (OCR)";
  sourceVersion: string | null;
  per100g: Per100g;
  /** Berapa dari 5 zat gizi inti yang tersedia. */
  completeness: "COMPLETE" | "PARTIAL" | "NONE";
  flags: string[];
};

// Batas kewajaran per 100 g. Di luar batas → null + flag, tidak ditebak.
const LIMITS: Record<keyof Per100g, number> = { calories: 950, carbohydrates: 100, protein: 100, fat: 100, fiber: 100 };

export function plausible(key: keyof Per100g, value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  if (typeof n !== "number" || !Number.isFinite(n) || n < 0 || n > LIMITS[key]) return null;
  return Math.round(n * 10000) / 10000;
}

export function buildCandidate(
  base: Omit<FoodCandidate, "per100g" | "completeness" | "flags">,
  raw: Record<keyof Per100g, unknown>,
): FoodCandidate {
  const per100g = {} as Per100g;
  const flags: string[] = [];
  for (const key of Object.keys(LIMITS) as (keyof Per100g)[]) {
    per100g[key] = plausible(key, raw[key]);
    if (raw[key] != null && raw[key] !== "" && per100g[key] === null) flags.push(`${key}_implausible`);
  }
  const known = Object.values(per100g).filter((v) => v !== null).length;
  return { ...base, per100g, completeness: known === 5 ? "COMPLETE" : known === 0 ? "NONE" : "PARTIAL", flags };
}

export class ProviderError extends Error {
  constructor(
    readonly code: "PROVIDER_NOT_CONFIGURED" | "PROVIDER_TIMEOUT" | "PROVIDER_UNAVAILABLE" | "PROVIDER_BAD_RESPONSE",
    message: string,
  ) {
    super(message);
  }
}

/** JSON (GET atau POST) dengan batas waktu dan ukuran; tidak mengikuti redirect (mencegah pindah host). */
type BoundedOptions = { allowedHost: string; timeoutMs?: number; maxBytes?: number; headers?: Record<string, string> };

async function boundedJson(fetchImpl: typeof fetch, url: URL, opts: BoundedOptions & { body?: unknown }): Promise<unknown> {
  if (url.protocol !== "https:" || url.hostname !== opts.allowedHost)
    throw new ProviderError("PROVIDER_BAD_RESPONSE", "Host penyedia tidak diizinkan.");
  const post = opts.body !== undefined;
  let res: Response;
  try {
    res = await fetchImpl(url, {
      ...(post ? { method: "POST", body: JSON.stringify(opts.body) } : {}),
      redirect: "error",
      signal: AbortSignal.timeout(opts.timeoutMs ?? 5000),
      headers: { accept: "application/json", "user-agent": "beOkay/1.0", ...(post ? { "content-type": "application/json" } : {}), ...opts.headers },
    });
  } catch (e) {
    const timedOut = e instanceof Error && (e.name === "TimeoutError" || e.name === "AbortError");
    throw new ProviderError(timedOut ? "PROVIDER_TIMEOUT" : "PROVIDER_UNAVAILABLE", "Penyedia data pangan tidak dapat dihubungi.");
  }
  if (!res.ok) throw new ProviderError("PROVIDER_UNAVAILABLE", `Penyedia membalas ${res.status}.`);
  const text = await res.text();
  if (text.length > (opts.maxBytes ?? 1_000_000)) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan penyedia terlalu besar.");
  try {
    return JSON.parse(text);
  } catch {
    throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan penyedia tidak valid.");
  }
}

export const boundedGetJson = (fetchImpl: typeof fetch, url: URL, opts: BoundedOptions): Promise<unknown> => boundedJson(fetchImpl, url, opts);

export const boundedPostJson = (fetchImpl: typeof fetch, url: URL, body: unknown, opts: BoundedOptions): Promise<unknown> => boundedJson(fetchImpl, url, { ...opts, body });
