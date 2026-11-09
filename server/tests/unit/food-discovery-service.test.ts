import { expect, mock, test } from "bun:test";

// Layanan lokal dimock agar uji ini tidak memerlukan database.
mock.module("../../src/features/nutrition/nutrition.service.ts", () => ({
  nutritionService: { searchFoods: async () => ({ items: [{ id: "local-1", name: "Nasi putih" }] }) },
}));
mock.module("../../src/features/consent/consent.service.ts", () => ({ consentService: { requireConsent: async () => {} } }));
const { createFoodDiscovery } = await import("../../src/features/food-discovery/food-discovery.service.ts");
const { ProviderError } = await import("../../src/features/food-discovery/food-candidate.ts");

const cand = (name: string) => ({ externalId: name, name, brand: null, source: "Open Food Facts" as const, sourceVersion: name, per100g: { calories: 1, carbohydrates: 1, protein: 1, fat: 1, fiber: 1 }, completeness: "COMPLETE" as const, flags: [] });

test("local first; external providers are not called unless requested", async () => {
  let called = 0;
  const svc = createFoodDiscovery({
    off: { search: async () => { called++; return []; }, byBarcode: async () => null },
    usda: { configured: false, search: async () => { called++; return []; } },
  });
  const r = await svc.discover("u", "nasi", false);
  expect(r.local).toHaveLength(1);
  expect(r.external.status).toBe("NOT_REQUESTED");
  expect(called).toBe(0);
});

test("provider failure degrades to partial without losing local or other results", async () => {
  const svc = createFoodDiscovery({
    off: { search: async () => [cand("Roti")], byBarcode: async () => null },
    usda: { configured: false, search: async () => { throw new ProviderError("PROVIDER_NOT_CONFIGURED", "x"); } },
  });
  const r = await svc.discover("u", "roti", true);
  expect(r.local).toHaveLength(1);
  expect(r.external.status).toBe("PARTIAL");
  expect(r.external.items).toHaveLength(1);
  expect(r.external.providers.find((p) => p.name.startsWith("USDA"))).toMatchObject({ status: "UNAVAILABLE", code: "PROVIDER_NOT_CONFIGURED" });
});

test("all providers down → UNAVAILABLE, still 200 with local results", async () => {
  const down = async () => { throw new ProviderError("PROVIDER_UNAVAILABLE", "x"); };
  const svc = createFoodDiscovery({ off: { search: down, byBarcode: down }, usda: { configured: true, search: down } });
  const r = await svc.discover("u", "x1", true);
  expect(r.external.status).toBe("UNAVAILABLE");
  expect(r.local).toHaveLength(1);
});

test("external lookups are rate limited per user and the window slides", async () => {
  let t = 0;
  const svc = createFoodDiscovery({
    off: { search: async () => [], byBarcode: async () => null },
    usda: { configured: false, search: async () => [] },
    now: () => t,
  });
  for (let i = 0; i < 20; i++) await svc.discover("u", "nasi", true);
  await expect(svc.discover("u", "nasi", true)).rejects.toMatchObject({ status: 429 });
  await svc.discover("other", "nasi", true); // another user is unaffected
  t += 11 * 60_000;
  await svc.discover("u", "nasi", true);
});

test("barcode: invalid code rejected before any network call; provider outage reported", async () => {
  let called = 0;
  const svc = createFoodDiscovery({
    off: { search: async () => [], byBarcode: async () => { called++; throw new ProviderError("PROVIDER_TIMEOUT", "x"); } },
    usda: { configured: false, search: async () => [] },
  });
  await expect(svc.barcode("u", "123")).rejects.toMatchObject({ code: "INVALID_BARCODE" });
  expect(called).toBe(0);
  expect(await svc.barcode("u", "4006381333931")).toMatchObject({ status: "UNAVAILABLE", candidate: null });
});
