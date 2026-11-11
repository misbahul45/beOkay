import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object) =>
  fetch(api + path, { method: body ? "POST" : "GET", headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(purposes: string[] = ["health_data_processing", "descriptive_summaries"]) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `stats-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (purposes.length) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  }
  return { id, token };
}
afterAll(async () => {
  await prisma.users.deleteMany({ where: { id: { in: users } } });
});
const J = async (r: Response) => (await r.json()) as any;
const hash = () => crypto.randomUUID().replaceAll("-", "").repeat(2);
const ago = (ms: number) => new Date(Date.now() - ms);
const HOUR = 3_600_000;

test("Statistics: auth, consent, period validation, ownership, exclusions, evidence envelope", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor(), partial = await actor(["health_data_processing"]);
  expect((await call("/api/me/insights/statistics")).status).toBe(401);
  expect((await call("/api/me/insights/statistics", partial.token)).status).toBe(403);
  expect((await call("/api/me/insights/statistics?days=5", a.token)).status).toBe(400);

  const empty = await J(await call("/api/me/insights/statistics?days=7", a.token));
  expect(empty.analyticsState).toBe("INSUFFICIENT_DATA");
  expect(empty.series).toHaveLength(7);
  expect(empty.insights).toEqual([]);
  expect(empty.statistics.find((s: any) => s.id === "activity.total_minutes").value).toBeNull();

  const glucose = (valueMgDl: number, measuredAt: Date, extra: { mealContext?: string; qualityStatus?: string; archivedAt?: Date } = {}) => ({ userId: a.id, source: "manual_glucometer", measurementType: "capillary_blood", originalUnit: "mg/dL", originalValue: valueMgDl, valueMgDl, measuredAt, createHash: hash(), mealContext: "fasting", ...extra });
  await prisma.glucoseObservation.createMany({
    data: [
      glucose(110, ago(1 * HOUR)),
      glucose(120, ago(2 * HOUR)),
      glucose(130, ago(3 * HOUR)),
      glucose(200, ago(4 * HOUR), { mealContext: "after_meal" }),
      { ...glucose(400, ago(5 * HOUR), { qualityStatus: "needs_review" }), qualityFlags: ["user_flagged"] },
      glucose(50, ago(6 * HOUR), { archivedAt: new Date() }),
    ],
  });
  await prisma.glucoseObservation.create({ data: { ...glucose(90, ago(HOUR)), userId: b.id } });
  const act = (min: number, startedAt: Date, extra: { qualityStatus?: string; userId?: string } = {}) => ({ userId: a.id, activityType: "walking", startedAt, endedAt: new Date(startedAt.getTime() + min * 60_000), durationMinutes: min, createHash: hash(), ...extra });
  await prisma.activitySession.createMany({ data: [act(30, ago(3 * HOUR)), act(45, ago(4 * HOUR), { qualityStatus: "needs_review" }), act(20, ago(9 * 24 * HOUR)), act(500, ago(3 * HOUR), { userId: b.id })] });
  const food = await J(await call("/api/me/foods", a.token, { name: "Statistik uji", source: "fixture", status: "user_reported", per100g: { calories: 200, carbohydrates: 30, protein: 5, fat: 2, fiber: null } }));
  expect((await call("/api/me/meals", a.token, { id: crypto.randomUUID(), category: "lunch", consumedAt: ago(5 * HOUR).toISOString(), items: [{ name: food.name, foodId: food.id, quantity: 150, unit: "g" }, { name: "Tanpa gizi", quantity: 1, unit: "portion" }] })).status).toBe(201);

  const r = await J(await call("/api/me/insights/statistics?days=7", a.token));
  const s = (id: string) => r.statistics.find((x: any) => x.id === id);
  expect(r.analysisVersion).toBe("stats-v1");
  expect(r.analyticsState).toBe("READY");
  expect(s("glucose.readings").value).toBe(4);
  expect(s("glucose.fasting_median").value).toBe(120);
  expect(s("glucose.fasting_median").sampleCount).toBe(3);
  expect(s("glucose.observed_range").detail).toEqual({ min: 110, max: 200 });
  expect(s("activity.total_minutes").value).toBe(30);
  expect(s("activity.total_minutes").comparison).toMatchObject({ value: 20, change: 10, direction: "UP" });
  expect(s("nutrition.logged_days").value).toBe(1);
  expect(s("nutrition.calories_per_logged_day").state).toBe("INSUFFICIENT_DATA");
  const mealDay = r.series.find((d: any) => d.meals > 0);
  expect(mealDay.nutrients.calories).toEqual({ value: 300, coverage: "PARTIAL" });
  expect(r.series.flatMap((d: any) => d.glucose.map((g: any) => g.value)).sort()).toEqual([110, 120, 130, 200]);
  for (const st of r.statistics) {
    expect(st.range).toEqual(r.period);
    expect(st.limitations.length).toBeGreaterThan(0);
    expect(typeof st.derivation).toBe("string");
  }

  const other = await J(await call("/api/me/insights/statistics?days=7", b.token));
  expect(other.statistics.find((x: any) => x.id === "glucose.readings").value).toBe(1);
  expect(other.statistics.find((x: any) => x.id === "activity.total_minutes").value).toBe(500);

  await prisma.userSettings.upsert({ where: { userId: a.id }, create: { userId: a.id, glucoseUnit: "mmol/L" }, update: { glucoseUnit: "mmol/L" } });
  const mmol = await J(await call("/api/me/insights/statistics?days=7", a.token));
  expect(mmol.glucoseUnit).toBe("mmol/L");
  expect(mmol.statistics.find((x: any) => x.id === "glucose.fasting_median").value).toBe(6.7);
});
