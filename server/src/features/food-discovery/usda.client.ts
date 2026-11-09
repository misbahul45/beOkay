import { boundedGetJson, buildCandidate, ProviderError, type FoodCandidate } from "./food-candidate.ts";

const HOST = "api.nal.usda.gov";
// Nomor zat gizi FoodData Central: energi 1008 (kcal), protein 1003, lemak 1004, karbohidrat 1005, serat 1079.
const NUTRIENT = { calories: 1008, protein: 1003, fat: 1004, carbohydrates: 1005, fiber: 1079 } as const;

type Food = { fdcId?: unknown; description?: unknown; brandOwner?: unknown; foodNutrients?: { nutrientId?: number; value?: unknown }[] };

/** Tanpa kunci API klien ini nonaktif dan melapor PROVIDER_NOT_CONFIGURED; tidak ada kunci bawaan. */
export function createUsdaClient(apiKey: string | undefined, fetchImpl: typeof fetch = fetch) {
  return {
    configured: Boolean(apiKey),
    async search(query: string, limit = 10): Promise<FoodCandidate[]> {
      if (!apiKey) throw new ProviderError("PROVIDER_NOT_CONFIGURED", "Penyedia USDA belum dikonfigurasi.");
      const url = new URL(`https://${HOST}/fdc/v1/foods/search`);
      url.search = new URLSearchParams({ query, pageSize: String(Math.min(limit, 10)), dataType: "Foundation,SR Legacy" }).toString();
      const body = (await boundedGetJson(fetchImpl, url, { allowedHost: HOST, headers: { "x-api-key": apiKey } })) as { foods?: Food[] };
      if (!Array.isArray(body.foods)) throw new ProviderError("PROVIDER_BAD_RESPONSE", "Balasan penyedia tidak valid.");
      return body.foods
        .map((f): FoodCandidate | null => {
          if (typeof f.description !== "string" || f.fdcId == null) return null;
          const val = (id: number) => f.foodNutrients?.find((n) => n.nutrientId === id)?.value;
          return buildCandidate(
            { externalId: String(f.fdcId), name: f.description.slice(0, 120), brand: typeof f.brandOwner === "string" ? f.brandOwner.slice(0, 80) : null, source: "USDA FoodData Central", sourceVersion: String(f.fdcId) },
            { calories: val(NUTRIENT.calories), carbohydrates: val(NUTRIENT.carbohydrates), protein: val(NUTRIENT.protein), fat: val(NUTRIENT.fat), fiber: val(NUTRIENT.fiber) },
          );
        })
        .filter((c): c is FoodCandidate => c !== null)
        .slice(0, limit);
    },
  };
}
