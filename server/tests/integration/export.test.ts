import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor() {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `ex-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;

test("Ekspor: hanya data sendiri, tanpa rahasia/hash, tetap bisa setelah consent ditarik, dibatasi lajunya", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor();
  expect((await call("/api/me/export")).status).toBe(401);

  await call("/api/me/glucose", a.token, { id: crypto.randomUUID(), originalValue: 110, originalUnit: "mg/dL", measuredAt: new Date(Date.now() - 60000).toISOString() });
  await call("/api/me/food-preferences", a.token, { kind: "allergy", term: "kacang" });
  await call("/api/me/reminders", a.token, { kind: "glucose", title: "Pagi", localTime: "07:30" });
  await call("/api/me/glucose", b.token, { id: crypto.randomUUID(), originalValue: 222, originalUnit: "mg/dL", measuredAt: new Date(Date.now() - 60000).toISOString() });

  const res = await call("/api/me/export", a.token);
  expect(res.status).toBe(200);
  expect(res.headers.get("content-disposition")).toContain("attachment");
  expect(res.headers.get("cache-control")).toContain("no-store");
  const text = await res.text();
  const bundle = JSON.parse(text);
  expect(bundle.format).toBe("beokay-export-v1");
  expect(bundle.counts).toMatchObject({ glucoseObservations: 1, foodPreferences: 1, reminders: 1 });
  expect(bundle.data.account.id).toBe(a.id);
  expect(bundle.data.glucoseObservations[0].originalValue ?? bundle.data.glucoseObservations[0].valueMgDl).toBeDefined();

  // Tidak ada data akun lain, rahasia, atau hash internal.
  expect(text).not.toContain(b.id);
  expect(text).not.toContain(a.token);
  expect(text).not.toContain("createHash");
  expect(text).not.toContain("payloadHash");
  expect(bundle.data).not.toHaveProperty("sessions");
  expect(bundle.data).not.toHaveProperty("accounts");
  expect(JSON.stringify(bundle.data.account)).not.toMatch(/password/i);

  // Diaudit.
  expect(await prisma.auditEvent.count({ where: { userId: a.id, eventType: "export_requested" } })).toBe(1);

  // Consent ditarik: ekspor tetap berjalan (hak atas data sendiri), tetapi API kesehatan terkunci.
  await call("/api/me/consents/withdraw", a.token, { purposes: ["health_data_processing"] });
  expect((await call("/api/me/glucose", a.token)).status).toBe(403);
  expect((await call("/api/me/export", a.token)).status).toBe(200);

  // Batas laju: 5 per jam per akun.
  for (let i = 0; i < 3; i++) expect((await call("/api/me/export", a.token)).status).toBe(200);
  expect((await call("/api/me/export", a.token)).status).toBe(429);
  expect((await call("/api/me/export", b.token)).status).toBe(200); // akun lain tidak terpengaruh
});
