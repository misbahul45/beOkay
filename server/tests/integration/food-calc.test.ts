import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(consent = true) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `food-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (consent) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
  }
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;

test("Food discovery (local), portion measures and calculator: ownership, provenance, unknown stays unknown", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor(), none = await actor(false);
  expect((await call("/api/me/foods/discover?q=nasi")).status).toBe(401);
  expect((await call("/api/me/foods/discover?q=nasi", none.token)).status).toBe(403);
  expect((await call("/api/me/nutrition/calculate", none.token, { items: [{ per100g: { calories: 1, carbohydrates: 1, protein: 1, fat: 1, fiber: 1 }, grams: 1 }] })).status).toBe(403);

  const food = await J(await call("/api/me/foods", a.token, { name: "Nasi uji sintetis", source: "Pengguna", sourceVersion: null, status: "user_reported", per100g: { calories: 130, carbohydrates: 28.2, protein: 2.7, fat: 0.3, fiber: null } }));
  expect(food.id).toBeTruthy();

  // Local-first discovery: external is NOT called unless requested; result says so.
  const found = await J(await call("/api/me/foods/discover?q=nasi%20uji", a.token));
  expect(found.local.map((f: any) => f.id)).toContain(food.id);
  expect(found.external).toMatchObject({ status: "NOT_REQUESTED", items: [] });
  expect((await J(await call("/api/me/foods/discover?q=nasi%20uji", b.token))).local.map((f: any) => f.id)).not.toContain(food.id);
  expect((await call("/api/me/foods/discover?q=n", a.token)).status).toBe(400);
  expect((await call("/api/me/foods/discover?q=nasi&external=yes", a.token)).status).toBe(400);

  // Barcode: invalid code rejected without touching any provider.
  expect((await call("/api/me/foods/barcode/1234567890123", a.token)).status).toBe(400);

  // Measures belong to the user; another user cannot see or use them.
  const m = await J(await call(`/api/me/foods/${food.id}/measures`, a.token, { label: "centong", grams: 100, basis: "user_estimate" }));
  expect(m).toMatchObject({ label: "centong", grams: 100, basis: "user_estimate" });
  expect((await J(await call(`/api/me/foods/${food.id}/measures`, a.token))).items).toHaveLength(1);
  expect((await call(`/api/me/foods/${food.id}/measures`, b.token)).status).toBe(404); // another user's food is not disclosed
  expect((await call(`/api/me/foods/${food.id}/measures`, b.token, { label: "x", grams: 5, basis: "weighed" })).status).toBe(404);
  expect((await call(`/api/me/foods/${food.id}/measures`, a.token, { label: "salah", grams: 0, basis: "weighed" })).status).toBe(400);

  // Calculate: measure × quantity, direct grams, unknown weight, and per-nutrient coverage.
  const calc = await J(await call("/api/me/nutrition/calculate", a.token, {
    items: [
      { foodId: food.id, quantity: 1.5, measureId: m.id },
      { foodId: food.id, grams: 100, gramsBasis: "weighed" },
      { foodId: food.id },
    ],
  }));
  expect(calc.computationVersion).toBe("portion-calc-v1");
  expect(calc.items[0]).toMatchObject({ grams: 150, gramsBasis: "user_estimate", reason: null });
  expect(calc.items[0].nutrition.calories).toBe(195);
  expect(calc.items[1]).toMatchObject({ grams: 100, gramsBasis: "weighed" });
  expect(calc.items[2]).toMatchObject({ grams: null, reason: "PORTION_WEIGHT_UNKNOWN" });
  expect(calc.items[2].nutrition.calories).toBeNull();
  expect(calc.totals.calories).toMatchObject({ value: 325, knownItems: 2, totalItems: 3, coverage: "PARTIAL" });
  expect(calc.totals.fiber).toMatchObject({ value: null, coverage: "UNKNOWN" }); // fiber unknown in the food, stays unknown

  // Validation and isolation.
  expect((await call("/api/me/nutrition/calculate", a.token, { items: [{ foodId: food.id, measureId: m.id }] })).status).toBe(400); // measure needs quantity
  expect((await call("/api/me/nutrition/calculate", a.token, { items: [{ foodId: food.id, measureId: m.id, quantity: 1, grams: 5 }] })).status).toBe(400);
  expect((await call("/api/me/nutrition/calculate", a.token, { items: [{ per100g: { calories: 1, carbohydrates: 1, protein: 1, fat: 1, fiber: 1 }, foodId: food.id, grams: 1 }] })).status).toBe(400);
  expect((await call("/api/me/nutrition/calculate", b.token, { items: [{ foodId: food.id, grams: 10 }] })).status).toBe(404);
  expect((await call("/api/me/nutrition/calculate", b.token, { items: [{ foodId: crypto.randomUUID(), grams: 10 }] })).status).toBe(404);
  const inline = await J(await call("/api/me/nutrition/calculate", b.token, { items: [{ name: "Inline", per100g: { calories: 200, carbohydrates: 20, protein: 10, fat: 5, fiber: 2 }, grams: 50, gramsBasis: "weighed" }] }));
  expect(inline.items[0].nutrition).toMatchObject({ calories: 100, protein: 5 });
});
