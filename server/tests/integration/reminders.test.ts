import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(consent = true) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `rm-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (consent) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing"] });
    await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  }
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;

test("Pengingat: CRUD berversi, validasi, batas, isolasi, consent, dan kejadian mendatang", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor(), none = await actor(false);
  expect((await call("/api/me/reminders")).status).toBe(401);
  expect((await call("/api/me/reminders", none.token)).status).toBe(403);

  const bad = (body: object) => call("/api/me/reminders", a.token, body);
  expect((await bad({ kind: "glucose", title: "x", localTime: "25:00" })).status).toBe(400);
  expect((await bad({ kind: "glucose", title: "x", localTime: "07:5" })).status).toBe(400);
  expect((await bad({ kind: "foo", title: "x", localTime: "07:30" })).status).toBe(400);
  expect((await bad({ kind: "glucose", title: "", localTime: "07:30" })).status).toBe(400);
  expect((await bad({ kind: "glucose", title: "x", localTime: "07:30", daysOfWeek: [0] })).status).toBe(400);
  expect((await bad({ kind: "glucose", title: "x", localTime: "07:30", extra: 1 })).status).toBe(400);

  const r1 = await J(await bad({ kind: "glucose", title: "Gula pagi", localTime: "07:30", daysOfWeek: [3, 1, 1, 2] }));
  expect(r1).toMatchObject({ kind: "glucose", localTime: "07:30", daysOfWeek: [1, 2, 3], enabled: true, version: 1, timezone: "Asia/Jakarta" });
  expect(r1.nextAt).toBeTruthy();
  expect(r1.lockScreen.body).not.toContain("Gula pagi"); // judul pengguna tidak ke layar kunci

  // Tulis langsung ke DB melanggar CHECK.
  const rejected = async (sql: string) => { try { await prisma.$executeRawUnsafe(sql); return false; } catch { return true; } };
  expect(await rejected(`UPDATE reminders SET local_time = '99:99' WHERE id = '${r1.id}'::uuid`)).toBe(true);
  expect(await rejected(`UPDATE reminders SET days_of_week = '{}' WHERE id = '${r1.id}'::uuid`)).toBe(true);

  // Isolasi.
  expect((await J(await call("/api/me/reminders", b.token))).items).toHaveLength(0);
  expect((await call(`/api/me/reminders/${r1.id}`, b.token, { expectedVersion: 1, enabled: false }, "PATCH")).status).toBe(404);

  // Versi usang ditolak; nonaktif menghilangkan nextAt dan kejadian mendatang.
  expect((await call(`/api/me/reminders/${r1.id}`, a.token, { expectedVersion: 7, enabled: false }, "PATCH")).status).toBe(409);
  expect((await call(`/api/me/reminders/${r1.id}`, a.token, { expectedVersion: 1 }, "PATCH")).status).toBe(400);
  let up = await J(await call("/api/me/reminders/upcoming?days=7", a.token));
  expect(up.items.length).toBeGreaterThan(0);
  expect(up.items.every((i: any) => i.reminderId === r1.id && i.localTime === "07:30")).toBe(true);
  expect(up.items.every((i: any) => [1, 2, 3].includes(new Date(i.localDate + "T00:00:00Z").getUTCDay() || 7))).toBe(true);
  const off = await J(await call(`/api/me/reminders/${r1.id}`, a.token, { expectedVersion: 1, enabled: false }, "PATCH"));
  expect(off).toMatchObject({ enabled: false, version: 2, nextAt: null });
  up = await J(await call("/api/me/reminders/upcoming", a.token));
  expect(up.items).toHaveLength(0);
  expect((await call("/api/me/reminders/upcoming?days=99", a.token)).status).toBe(400);

  // Batas pengingat aktif.
  for (let i = 0; i < 19; i++) expect((await bad({ kind: "custom", title: `P${i}`, localTime: "08:00" })).status).toBe(201);
  expect((await bad({ kind: "custom", title: "kelebihan", localTime: "08:00" })).status).toBe(422);
  // Arsip membebaskan kuota.
  const list = await J(await call("/api/me/reminders", a.token));
  expect(list.items).toHaveLength(20);
  await call(`/api/me/reminders/${list.items[0].id}`, a.token, { expectedVersion: list.items[0].version, archived: true }, "PATCH");
  expect((await bad({ kind: "custom", title: "muat lagi", localTime: "08:00" })).status).toBe(201);
});
