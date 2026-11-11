import { ProviderError } from "./food-candidate.ts";
import { safeResultUrl } from "./web-search.client.ts";

const HOST = "api.firecrawl.dev";

export type FirecrawlPage = { title: string; url: string; host: string; snippet: string; markdown: string };

const clean = (s: unknown, max: number) =>
  typeof s === "string"
    ? s
        .replace(/<[^>]*>/g, "")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, max)
    : "";

export function createFirecrawlClient(apiKey: string | undefined, fetchImpl: typeof fetch = fetch) {
  return {
    configured: Boolean(apiKey),
    async search(query: string, limit = 4): Promise<FirecrawlPage[]> {
      if (!apiKey) throw new ProviderError("PROVIDER_NOT_CONFIGURED", "Pencarian web belum dikonfigurasi.");
      const url = new URL(`https://${HOST}/v2/search`);
      let res: Response;
      try {
        res = await fetchImpl(url, {
          method: "POST",
          redirect: "error",
          signal: AbortSignal.timeout(20_000),
          headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json", accept: "application/json", "user-agent": "beOkay/1.0" },
          body: JSON.stringify({ query: query.slice(0, 160), limit: Math.min(Math.max(limit, 1), 5), scrapeOptions: { formats: ["markdown"], onlyMainContent: true } }),
        });
      } catch (e) {
        const timedOut = e instanceof Error && (e.name === "TimeoutError" || e.name === "AbortError");
        throw new ProviderError(timedOut ? "PROVIDER_TIMEOUT" : "PROVIDER_UNAVAILABLE", "Layanan pencarian web tidak dapat dihubungi.");
      }
      if (!res.ok) throw new ProviderError("PROVIDER_UNAVAILABLE", `Penyedia membalas ${res.status}.`);
      const text = await res.text();
      if (text.length > 3_000_000) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan penyedia terlalu besar.");
      let body: { success?: unknown; data?: unknown };
      try {
        body = JSON.parse(text);
      } catch {
        throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan penyedia tidak valid.");
      }
      const data = body.data as { web?: unknown } | unknown[] | undefined;
      const items = Array.isArray(data) ? data : Array.isArray((data as { web?: unknown } | undefined)?.web) ? ((data as { web: unknown[] }).web) : null;
      if (body.success !== true || !items) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan penyedia tidak valid.");
      const out: FirecrawlPage[] = [];
      for (const raw of items as Record<string, unknown>[]) {
        const u = safeResultUrl(raw.url);
        const title = clean(raw.title ?? (raw.metadata as Record<string, unknown> | undefined)?.title, 160);
        if (!u || !title) continue;
        out.push({
          title,
          url: u.toString(),
          host: u.hostname,
          snippet: clean(raw.description, 300),
          markdown: typeof raw.markdown === "string" ? raw.markdown.slice(0, 60_000) : "",
        });
        if (out.length >= limit) break;
      }
      return out;
    },
  };
}
