import { z } from "zod";
import { ProviderError } from "../food-discovery/food-candidate.ts";

export const EMBEDDING_DIMENSIONS = 1024;
const HOST = "api.mistral.ai";
const response = z.object({ data: z.array(z.object({ index: z.number().int(), embedding: z.array(z.number()) })).min(1) });

/**
 * Embedding Mistral (host dipaku, kunci hanya di header). Dimensi dan nilai diperiksa: vektor yang salah
 * panjang atau berisi NaN ditolak, bukan disimpan.
 */
export function createEmbeddingClient(config: { apiKey: string | undefined; model: string }, fetchImpl: typeof fetch = fetch) {
  return {
    get configured() {
      return Boolean(config.apiKey);
    },
    get model() {
      return config.model;
    },
    async embed(texts: string[]): Promise<number[][]> {
      if (!config.apiKey) throw new ProviderError("PROVIDER_NOT_CONFIGURED", "Embedding belum dikonfigurasi di server.");
      if (texts.length === 0) return [];
      if (texts.length > 64) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Terlalu banyak teks dalam satu permintaan.");
      let res: Response;
      try {
        res = await fetchImpl(new URL(`https://${HOST}/v1/embeddings`), {
          method: "POST",
          redirect: "error",
          signal: AbortSignal.timeout(20_000),
          headers: { "content-type": "application/json", accept: "application/json", authorization: `Bearer ${config.apiKey}` },
          body: JSON.stringify({ model: config.model, input: texts }),
        });
      } catch (e) {
        const timedOut = e instanceof Error && (e.name === "TimeoutError" || e.name === "AbortError");
        throw new ProviderError(timedOut ? "PROVIDER_TIMEOUT" : "PROVIDER_UNAVAILABLE", "Layanan embedding tidak dapat dihubungi.");
      }
      if (!res.ok) throw new ProviderError("PROVIDER_UNAVAILABLE", `Layanan embedding membalas ${res.status}.`);
      const raw = await res.text();
      if (raw.length > 4_000_000) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan terlalu besar.");
      let json: unknown;
      try {
        json = JSON.parse(raw);
      } catch {
        throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan embedding tidak valid.");
      }
      const parsed = response.safeParse(json);
      if (!parsed.success || parsed.data.data.length !== texts.length) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan embedding tidak sesuai.");
      const ordered = [...parsed.data.data].sort((a, b) => a.index - b.index).map((d) => d.embedding);
      for (const v of ordered) {
        if (v.length !== EMBEDDING_DIMENSIONS || v.some((x) => !Number.isFinite(x))) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Vektor embedding tidak valid.");
      }
      return ordered;
    },
  };
}

/** Literal pgvector, mis. "[0.1,0.2]". Hanya angka terhingga yang diizinkan. */
export function toVectorLiteral(v: number[]): string {
  if (v.length !== EMBEDDING_DIMENSIONS || v.some((x) => !Number.isFinite(x))) throw new Error("INVALID_VECTOR");
  return `[${v.join(",")}]`;
}
