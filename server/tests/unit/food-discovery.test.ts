import { expect, test } from "bun:test";
import { validGtin } from "../../src/features/food-discovery/barcode.ts";
import { plausible, ProviderError } from "../../src/features/food-discovery/food-candidate.ts";
import { createOffClient } from "../../src/features/food-discovery/off.client.ts";
import { createUsdaClient } from "../../src/features/food-discovery/usda.client.ts";
import { calculateMeal, calculatePortion } from "../../src/features/nutrition/portion.model.ts";

const json = (body: unknown, init: ResponseInit = {}) => new Response(JSON.stringify(body), { status: 200, ...init });

test("GTIN check digit validation", () => {
  expect(validGtin("8999999999999")).toBe(false); // wrong check digit
  expect(validGtin("4006381333931")).toBe(true); // valid EAN-13
  expect(validGtin("96385074")).toBe(true); // valid EAN-8
  expect(validGtin("12345")).toBe(false);
  expect(validGtin("40063813339a1")).toBe(false);
});

test("plausibility keeps unknown as null, never zero or a guess", () => {
  expect(plausible("calories", "250")).toBe(250);
  expect(plausible("calories", 5000)).toBeNull();
  expect(plausible("protein", -1)).toBeNull();
  expect(plausible("fat", "")).toBeNull();
  expect(plausible("fiber", undefined)).toBeNull();
  expect(plausible("carbohydrates", 0)).toBe(0); // a real zero is kept
});

test("Open Food Facts: normalizes, nulls implausible, never calls another host", async () => {
  const seen: string[] = [];
  const off = createOffClient((async (url: URL) => {
    seen.push(url.hostname);
    return json({
      products: [
        { code: "1", product_name: "Roti uji", brands: "Merek A, Merek B", nutriments: { "energy-kcal_100g": 260, carbohydrates_100g: 50, proteins_100g: 8, fat_100g: 3, fiber_100g: 2 } },
        { code: "2", product_name: "Aneh", nutriments: { "energy-kcal_100g": 9999, proteins_100g: 5 } },
        { code: "3", product_name: "" },
        { product_name: "Tanpa kode" },
      ],
    });
  }) as unknown as typeof fetch);
  const items = await off.search("roti");
  expect(seen).toEqual(["world.openfoodfacts.org"]);
  expect(items).toHaveLength(2);
  expect(items[0]).toMatchObject({ completeness: "COMPLETE", brand: "Merek A", source: "Open Food Facts" });
  expect(items[1]!.per100g.calories).toBeNull();
  expect(items[1]!.flags).toContain("calories_implausible");
  expect(items[1]).toMatchObject({ completeness: "PARTIAL" });
});

test("providers fail closed: timeout, bad status, oversize, malformed", async () => {
  const make = (impl: () => Promise<Response>) => createOffClient(impl as unknown as typeof fetch);
  const code = async (p: Promise<unknown>) => ((await p.catch((e) => e)) as ProviderError).code;
  expect(await code(make(async () => { throw Object.assign(new Error("t"), { name: "TimeoutError" }); }).search("x"))).toBe("PROVIDER_TIMEOUT");
  expect(await code(make(async () => new Response("no", { status: 503 })).search("x"))).toBe("PROVIDER_UNAVAILABLE");
  expect(await code(make(async () => new Response("x".repeat(1_100_000))).search("x"))).toBe("PROVIDER_BAD_RESPONSE");
  expect(await code(make(async () => new Response("<html>")).search("x"))).toBe("PROVIDER_BAD_RESPONSE");
  expect(await code(make(async () => json({ nope: 1 })).search("x"))).toBe("PROVIDER_BAD_RESPONSE");
});

test("barcode lookup: found, not found, code is URL-encoded into a fixed host", async () => {
  let called = "";
  const off = createOffClient((async (url: URL) => {
    called = url.pathname;
    return json(url.pathname.includes("4006381333931") ? { status: 1, product: { product_name: "Pensil", nutriments: {} } } : { status: 0 });
  }) as unknown as typeof fetch);
  const found = await off.byBarcode("4006381333931");
  expect(called).toBe("/api/v2/product/4006381333931.json");
  expect(found).toMatchObject({ externalId: "4006381333931", completeness: "NONE" });
  expect(await off.byBarcode("96385074")).toBeNull();
});

test("USDA is disabled without a key and sends the key only as a header", async () => {
  await expect(createUsdaClient(undefined).search("apple")).rejects.toMatchObject({ code: "PROVIDER_NOT_CONFIGURED" });
  let url = "", header = "";
  const usda = createUsdaClient("synthetic-test-key", (async (u: URL, init: RequestInit) => {
    url = u.toString();
    header = (init.headers as Record<string, string>)["x-api-key"]!;
    return json({ foods: [{ fdcId: 1, description: "Apple, raw", foodNutrients: [{ nutrientId: 1008, value: 52 }, { nutrientId: 1003, value: 0.26 }, { nutrientId: 1004, value: 0.17 }, { nutrientId: 1005, value: 13.8 }] }] });
  }) as unknown as typeof fetch);
  const [apple] = await usda.search("apple");
  expect(url).not.toContain("synthetic-test-key");
  expect(header).toBe("synthetic-test-key");
  expect(apple).toMatchObject({ source: "USDA FoodData Central", completeness: "PARTIAL", per100g: { calories: 52, fiber: null } });
});

test("portion calculator: weight × per-100g with Decimal precision, unknown stays null", () => {
  const per100g = { calories: 130, carbohydrates: 28.2, protein: 2.7, fat: 0.3, fiber: null };
  const direct = calculatePortion({ name: "Nasi", per100g, grams: 150, gramsBasis: "weighed" });
  expect(direct).toMatchObject({ grams: 150, gramsBasis: "weighed", reason: null });
  expect(direct.nutrition.calories).toBe(195);
  expect(direct.nutrition.carbohydrates).toBe(42.3);
  expect(direct.nutrition.fiber).toBeNull(); // unknown ≠ 0

  const measured = calculatePortion({ name: "Nasi", per100g, quantity: 1.5, measure: { id: "m", label: "centong", grams: 100.3333, basis: "user_estimate" } });
  expect(measured.grams).toBe(150.5); // 1.5 × 100.3333 = 150.49995 → 4 decimals
  expect(measured.gramsBasis).toBe("user_estimate");

  const unknown = calculatePortion({ name: "Nasi", per100g });
  expect(unknown).toMatchObject({ grams: null, gramsBasis: null, reason: "PORTION_WEIGHT_UNKNOWN" });
  expect(Object.values(unknown.nutrition).every((v) => v === null)).toBe(true);

  const defaultBasis = calculatePortion({ name: "Nasi", per100g, grams: 100 });
  expect(defaultBasis.gramsBasis).toBe("user_estimate"); // never claims "weighed" unless stated
});

test("meal totals report coverage when an item has no known weight", () => {
  const per100g = { calories: 100, carbohydrates: 10, protein: 5, fat: 2, fiber: 1 };
  const { totals } = calculateMeal([
    { name: "A", per100g, grams: 200, gramsBasis: "weighed" },
    { name: "B", per100g },
  ]);
  expect(totals.calories).toMatchObject({ value: 200, knownItems: 1, totalItems: 2, coverage: "PARTIAL" });
  expect(calculateMeal([{ name: "B", per100g }]).totals.calories).toMatchObject({ value: null, coverage: "UNKNOWN" });
});
