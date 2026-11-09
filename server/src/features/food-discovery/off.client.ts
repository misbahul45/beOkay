import { boundedGetJson, buildCandidate, ProviderError, type FoodCandidate } from "./food-candidate.ts";

const HOST = "world.openfoodfacts.org";
const FIELDS = "code,product_name,brands,nutriments";

type Product = { code?: unknown; product_name?: unknown; brands?: unknown; nutriments?: Record<string, unknown> };

function toCandidate(p: Product): FoodCandidate | null {
  const code = typeof p.code === "string" ? p.code : null;
  const name = typeof p.product_name === "string" ? p.product_name.trim() : "";
  if (!code || !name) return null;
  const n = p.nutriments ?? {};
  return buildCandidate(
    {
      externalId: code,
      name: name.slice(0, 120),
      brand: typeof p.brands === "string" && p.brands.trim() ? p.brands.split(",")[0]!.trim().slice(0, 80) : null,
      source: "Open Food Facts",
      sourceVersion: code,
    },
    {
      calories: n["energy-kcal_100g"],
      carbohydrates: n["carbohydrates_100g"],
      protein: n["proteins_100g"],
      fat: n["fat_100g"],
      fiber: n["fiber_100g"],
    },
  );
}

/** Host tetap (tidak pernah dari input pengguna); hanya GET, batas waktu dan ukuran. */
export function createOffClient(fetchImpl: typeof fetch = fetch) {
  return {
    async search(query: string, limit = 10): Promise<FoodCandidate[]> {
      const url = new URL(`https://${HOST}/cgi/search.pl`);
      url.search = new URLSearchParams({ search_terms: query, search_simple: "1", action: "process", json: "1", page_size: String(Math.min(limit, 10)), fields: FIELDS }).toString();
      const body = (await boundedGetJson(fetchImpl, url, { allowedHost: HOST })) as { products?: Product[] };
      if (!Array.isArray(body.products)) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan penyedia tidak valid.");
      return body.products.map(toCandidate).filter((c): c is FoodCandidate => c !== null).slice(0, limit);
    },
    async byBarcode(code: string): Promise<FoodCandidate | null> {
      const url = new URL(`https://${HOST}/api/v2/product/${encodeURIComponent(code)}.json`);
      url.search = new URLSearchParams({ fields: FIELDS }).toString();
      const body = (await boundedGetJson(fetchImpl, url, { allowedHost: HOST })) as { status?: number; product?: Product };
      if (body.status !== 1 || !body.product) return null;
      return toCandidate({ ...body.product, code: body.product.code ?? code });
    },
  };
}
