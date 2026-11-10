import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(consent = true) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `ai-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (consent) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/consent-policies/current", token);
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
    await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  }
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;
const ago = (min: number) => new Date(Date.now() - min * 60_000).toISOString();
const sess = (externalId: string, startMinAgo: number, duration = 30, extra: object = {}) => ({ externalId, activityType: "walking", startedAt: ago(startMinAgo), durationMinutes: duration, ...extra });

test("Impor aktivitas perangkat: idempoten, device_reported, tabrakan waktu → needs_review, terisolasi, dihitung di ringkasan", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor(), none = await actor(false);
  const imp = (token: string | undefined, body: object) => call("/api/me/activities/import", token, body);
  expect((await imp(undefined, { source: "health_connect", sessions: [sess("x", 120)] })).status).toBe(401);
  expect((await imp(none.token, { source: "health_connect", sessions: [sess("x", 120)] })).status).toBe(403);

  // Validasi.
  expect((await imp(a.token, { source: "fitbit", sessions: [sess("x", 120)] })).status).toBe(400);
  expect((await imp(a.token, { source: "health_connect", sessions: [] })).status).toBe(400);
  expect((await imp(a.token, { source: "health_connect", sessions: [sess("d", 120), sess("d", 300)] })).status).toBe(400);
  expect((await imp(a.token, { source: "health_connect", sessions: [{ ...sess("y", 120), extra: 1 }] })).status).toBe(400);

  // Catatan manual 90-60 menit lalu; impor yang bertabrakan ditandai, yang tidak bertabrakan dihitung.
  expect((await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "walking", startedAt: ago(90), durationMinutes: 30 })).status).toBe(201);
  const body = { source: "health_connect", sessions: [sess("hc-1", 85, 20, { steps: 2200, distanceKm: 1.6 }), sess("hc-2", 300, 40), sess("hc-3", 1, 60)] };
  const res = await J(await imp(a.token, body));
  const by = Object.fromEntries(res.results.map((r: any) => [r.externalId, r]));
  expect(by["hc-1"]).toMatchObject({ status: "CREATED_NEEDS_REVIEW", reason: "TIME_OVERLAP" });
  expect(by["hc-2"].status).toBe("CREATED");
  expect(by["hc-3"]).toMatchObject({ status: "REJECTED", reason: "ACTIVITY_NOT_COMPLETED" });
  expect(res.summary).toEqual({ created: 1, createdNeedsReview: 1, duplicate: 0, rejected: 1 });

  // Status dan sumber di basis data; metrik yang tidak dikirim tetap null (tidak dikarang).
  const rows = await prisma.activitySession.findMany({ where: { userId: a.id, source: "health_connect" }, orderBy: { externalId: "asc" } });
  expect(rows.map((r) => [r.externalId, r.qualityStatus])).toEqual([["hc-1", "needs_review"], ["hc-2", "device_reported"]]);
  expect(rows[1]!.steps).toBeNull();
  expect(rows[1]!.distanceKm).toBeNull();
  expect(rows[0]!.steps).toBe(2200);

  // Mengulang impor yang sama tidak membuat baris baru.
  const again = await J(await imp(a.token, body));
  expect(again.summary).toMatchObject({ created: 0, createdNeedsReview: 0, duplicate: 2, rejected: 1 });
  expect(await prisma.activitySession.count({ where: { userId: a.id } })).toBe(3);

  // Ringkasan menghitung sesi perangkat yang sah dan mengecualikan needs_review.
  const localDate = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" }).format(new Date(Date.now() - 300 * 60_000));
  const sum = await J(await call(`/api/me/activities/summary?date=${localDate}`, a.token));
  expect(sum.durationMinutes).toBeGreaterThanOrEqual(40);
  expect(sum.reviewCount).toBeGreaterThanOrEqual(0);

  // Pengguna mengonfirmasi sesi yang bertabrakan: tidak pernah menjadi user_reported, melainkan device_reported.
  const flagged = await prisma.activitySession.findFirstOrThrow({ where: { userId: a.id, externalId: "hc-1" } });
  const patched = await call(`/api/me/activities/${flagged.id}`, a.token, { expectedVersion: 1, reason: "Bukan duplikat", qualityStatus: "user_reported" }, "PATCH");
  expect(patched.status).toBe(200);
  expect((await J(patched)).qualityStatus).toBe("device_reported");

  // Terisolasi per akun: externalId yang sama di akun lain adalah baris terpisah.
  const other = await J(await imp(b.token, { source: "health_connect", sessions: [sess("hc-2", 300, 40)] }));
  expect(other.results[0].status).toBe("CREATED");
  expect(await prisma.activitySession.count({ where: { userId: b.id } })).toBe(1);

  // CHECK basis data: impor tidak boleh mengaku user_reported; manual tidak boleh punya external_id.
  const bad = async (sql: string) => { try { await prisma.$executeRawUnsafe(sql); return false; } catch { return true; } };
  const base = (cols: string, vals: string) => `INSERT INTO activity_sessions (user_id,activity_type,started_at,ended_at,duration_minutes,create_hash,updated_at,${cols}) VALUES ('${a.id}','walking','2026-01-01T00:00:00Z','2026-01-01T00:10:00Z',10,'${"a".repeat(64)}',now(),${vals})`;
  expect(await bad(base("source,external_id,quality_status", `'health_connect','z1','user_reported'`))).toBe(true);
  expect(await bad(base("source,external_id,quality_status", `'manual','z2','user_reported'`))).toBe(true);
  expect(await bad(base("source,quality_status", `'apple_health','user_reported'`))).toBe(true);
  expect(await bad(base("source,external_id,quality_status", `'fitbit','z3','device_reported'`))).toBe(true);
});
