import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object) =>
  fetch(api + path, { method: body ? "POST" : "GET", headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(consent = true) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `trend-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (consent) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
  }
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;
const hash = () => crypto.randomUUID().replaceAll("-", "").repeat(2);
const ago = (ms: number) => new Date(Date.now() - ms);

test("Trends: consent, input range, ownership, unknown stays null, archived/review rows excluded", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor(), none = await actor(false);
  expect((await call("/api/me/trends")).status).toBe(401);
  expect((await call("/api/me/trends", none.token)).status).toBe(403);
  expect((await call("/api/me/trends?days=5", a.token)).status).toBe(400);

  // Akun kosong: tidak ada angka karangan.
  const empty = await J(await call("/api/me/trends?days=7", a.token));
  expect(empty.analyticsState).toBe("INSUFFICIENT_DATA");
  expect(empty.series).toHaveLength(7);
  expect(empty.activity.totalMinutes).toBeNull();
  expect(empty.glucose.min).toBeNull();

  const row = (extra: { valueMgDl: number; originalValue: number; measuredAt: Date; qualityStatus?: string; qualityFlags?: string[]; archivedAt?: Date }) => ({ userId: a.id, source: "manual_glucometer", measurementType: "capillary_blood", originalUnit: "mg/dL", createHash: hash(), ...extra });
  await prisma.glucoseObservation.createMany({
    data: [
      row({ valueMgDl: 100, originalValue: 100, measuredAt: ago(3_600_000) }),
      row({ valueMgDl: 140, originalValue: 140, measuredAt: ago(1_800_000) }),
      row({ valueMgDl: 300, originalValue: 300, measuredAt: ago(1_000_000), qualityStatus: "needs_review", qualityFlags: ["user_flagged"] }), // dikecualikan
      row({ valueMgDl: 250, originalValue: 250, measuredAt: ago(900_000), archivedAt: new Date() }), // diarsipkan
    ],
  });
  const act = (min: number, extra: { qualityStatus?: string; startedAt?: Date } = {}) => { const startedAt = extra.startedAt ?? ago(7_200_000); return { userId: a.id, activityType: "walking", durationMinutes: min, createHash: hash(), ...extra, startedAt, endedAt: new Date(startedAt.getTime() + min * 60_000) }; };
  await prisma.activitySession.createMany({ data: [act(30), act(20), act(99, { qualityStatus: "needs_review" })] });
  // Pembanding: periode sebelumnya (±10 hari lalu) → 15 menit.
  await prisma.activitySession.create({ data: act(15, { startedAt: ago(10 * 86_400_000) }) });

  const food = await J(await call("/api/me/foods", a.token, { name: "Trend uji", source: "fixture", status: "user_reported", per100g: { calories: 200, carbohydrates: 30, protein: 5, fat: null, fiber: null } }));
  await call("/api/me/meals", a.token, { id: crypto.randomUUID(), category: "lunch", consumedAt: ago(5_000_000).toISOString(), items: [{ name: food.name, foodId: food.id, quantity: 150, unit: "g" }, { name: "Tanpa gizi", quantity: 1, unit: "portion" }] });

  const t = await J(await call("/api/me/trends?days=7", a.token));
  const today = t.series[6];
  expect(today.glucose).toEqual({ count: 2, min: 100, max: 140 }); // review/arsip tidak ikut
  expect(today.activityMinutes).toBe(50); // 99 menit "needs_review" tidak ikut
  expect(today.meals.count).toBe(1);
  expect(today.meals.carbs.coverage).toBe("PARTIAL"); // satu item tanpa gizi
  expect(t.activity).toMatchObject({ totalMinutes: 50, previousTotalMinutes: 15 });
  expect(t.notes.map((n: any) => n.code)).toContain("ACTIVITY_MORE");
  expect(JSON.stringify(t)).not.toMatch(/inRange|score|adherence/i);

  // Pengguna lain tidak melihat data A.
  const other = await J(await call("/api/me/trends?days=7", b.token));
  expect(other.analyticsState).toBe("INSUFFICIENT_DATA");
  expect(other.glucose.readings).toBe(0);

  for (const days of [14, 30, 90]) expect((await call(`/api/me/trends?days=${days}`, a.token)).status).toBe(200);
});
