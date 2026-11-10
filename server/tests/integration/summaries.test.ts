import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor() {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `sum-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });

test("Ringkasan harian disimpan sebagai proyeksi turunan, jadi STALE saat data sumber berubah, dan terisolasi per akun", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor();
  const date = "2026-11-09";
  expect((await call(`/api/me/summaries/daily?date=${date}`)).status).toBe(401);

  let res = await call(`/api/me/summaries/daily?date=${date}`, a.token);
  expect(res.status).toBe(200);
  let row = await prisma.summaryProjection.findFirst({ where: { userId: a.id, kind: "daily" } });
  expect(row).toMatchObject({ coverageStatus: "UNKNOWN", analyticsState: "INSUFFICIENT_DATA", freshnessStatus: "CURRENT" });

  // Mencatat glukosa mengubah data sumber: proyeksi ditandai STALE, lalu CURRENT lagi setelah dibaca.
  const created = await call("/api/me/glucose", a.token, { id: crypto.randomUUID(), originalValue: 110, originalUnit: "mg/dL", measuredAt: "2026-11-09T01:00:00.000Z" });
  expect(created.status).toBe(201);
  row = await prisma.summaryProjection.findFirst({ where: { userId: a.id, kind: "daily" } });
  expect(row?.freshnessStatus).toBe("STALE");
  res = await call(`/api/me/summaries/daily?date=${date}`, a.token);
  expect(res.status).toBe(200);
  row = await prisma.summaryProjection.findFirst({ where: { userId: a.id, kind: "daily" } });
  expect(row).toMatchObject({ coverageStatus: "PARTIAL", analyticsState: "READY", freshnessStatus: "CURRENT" });
  expect(await prisma.summaryProjection.count({ where: { userId: a.id, kind: "daily" } })).toBe(1);

  // Akun lain tidak memiliki proyeksi milik A.
  expect(await prisma.summaryProjection.count({ where: { userId: b.id } })).toBe(0);
});

test("Insight kontekstual: butuh consent, hanya data sendiri, dan berbasis catatan yang ada", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor();
  expect((await call("/api/me/insights/contextual")).status).toBe(401);
  const empty = (await (await call("/api/me/insights/contextual", a.token)).json()) as any;
  expect(empty.items.every((i: any) => !["GLUCOSE_LOG_GAP", "LOGGING_STREAK"].includes(i.code))).toBe(true);
  expect(empty.rulesVersion).toBe("contextual-rules-v1");

  // Tiga hari berturut-turut ada catatan -> rangkaian; akun lain tidak terpengaruh.
  for (const offset of [0, 1, 2]) {
    const when = new Date(Date.now() - offset * 86_400_000 - 120_000).toISOString();
    expect((await call("/api/me/glucose", a.token, { id: crypto.randomUUID(), originalValue: 105, originalUnit: "mg/dL", measuredAt: when })).status).toBe(201);
  }
  const res = (await (await call("/api/me/insights/contextual", a.token)).json()) as any;
  expect(res.items.map((i: any) => i.code)).toContain("LOGGING_STREAK");
  expect(JSON.stringify(res).toLowerCase()).not.toMatch(/mg\/dl|hipo|hiper|tinggi|rendah/);
  const other = (await (await call("/api/me/insights/contextual", b.token)).json()) as any;
  expect(other.items.map((i: any) => i.code)).not.toContain("LOGGING_STREAK");
});
