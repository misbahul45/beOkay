import { boundedPostJson, ProviderError } from "./food-candidate.ts";

const HOST = "api.tavily.com";

export type WebResult = {
  title: string;
  url: string;
  host: string;
  snippet: string;
  /** Hasil web adalah bacaan untuk manusia: tidak ditinjau, dan angkanya tidak pernah dipakai sebagai data gizi. */
  reviewed: false;
  usableForNutrition: false;
};

const stripTags = (s: string) => s.replace(/<[^>]*>/g, "").replace(/&(amp|lt|gt|quot|#39);/g, (m) => ({ "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'" })[m]!).replace(/\s+/g, " ").trim();

/** Hanya tautan https tanpa kredensial dan tanpa host IP/lokal; selain itu dibuang. */
export function safeResultUrl(raw: unknown): URL | null {
  if (typeof raw !== "string" || raw.length > 500) return null;
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return null;
  }
  if (u.protocol !== "https:" || u.username || u.password || u.port) return null;
  const h = u.hostname.toLowerCase();
  if (h === "localhost" || h.endsWith(".local") || h.endsWith(".internal") || /^\d{1,3}(\.\d{1,3}){3}$/.test(h) || h.includes(":") || !h.includes(".")) return null;
  return u;
}

/**
 * Pencarian web terkontrol (Tavily Search API). Host dipaku, tanpa redirect, kunci hanya di header.
 * Hanya judul, tautan, dan cuplikan yang dikembalikan; halaman tidak pernah diambil oleh server.
 */
export function createWebSearchClient(apiKey: string | undefined, fetchImpl: typeof fetch = fetch) {
  return {
    configured: Boolean(apiKey),
    async search(query: string, limit = 5): Promise<WebResult[]> {
      if (!apiKey) throw new ProviderError("PROVIDER_NOT_CONFIGURED", "Pencarian web belum dikonfigurasi.");
      const request = {
        query: query.slice(0, 120),
        max_results: Math.min(limit, 8),
        search_depth: "basic",
        topic: "general",
        country: "indonesia",
        include_answer: false,
        include_raw_content: false,
        include_images: false,
      };
      const body = (await boundedPostJson(fetchImpl, new URL(`https://${HOST}/search`), request, { allowedHost: HOST, timeoutMs: 8000, maxBytes: 600_000, headers: { authorization: `Bearer ${apiKey}` } })) as { results?: { title?: unknown; url?: unknown; content?: unknown }[] };
      const results = body.results;
      if (!Array.isArray(results)) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan penyedia tidak valid.");
      const out: WebResult[] = [];
      for (const r of results) {
        const u = safeResultUrl(r.url);
        if (!u || typeof r.title !== "string") continue;
        out.push({
          title: stripTags(r.title).slice(0, 140),
          url: u.toString(),
          host: u.hostname,
          snippet: typeof r.content === "string" ? stripTags(r.content).slice(0, 300) : "",
          reviewed: false,
          usableForNutrition: false,
        });
        if (out.length >= limit) break;
      }
      return out;
    },
  };
}
