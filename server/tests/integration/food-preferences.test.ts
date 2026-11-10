import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(consent = true) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `fp-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (consent) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
  }
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;

test("Preferensi makanan: CRUD berversi, idempoten, terisolasi, butuh consent, dan dipakai pencarian", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor(), none = await actor(false);

  expect((await call("/api/me/food-preferences")).status).toBe(401);
  expect((await call("/api/me/food-preferences", none.token)).status).toBe(403);
  expect((await call("/api/me/food-preferences", none.token, { kind: "allergy", term: "kacang" })).status).toBe(403);

  // Validasi: kind tak dikenal, istilah terlalu pendek, kolom asing.
  expect((await call("/api/me/food-preferences", a.token, { kind: "foo", term: "kacang" })).status).toBe(400);
  expect((await call("/api/me/food-preferences", a.token, { kind: "allergy", term: "k" })).status).toBe(400);
  expect((await call("/api/me/food-preferences", a.token, { kind: "allergy", term: "kacang", severity: "soft" })).status).toBe(400);

  // Alergi selalu strict; alias "peanut" -> "kacang"; pembuatan ulang idempoten.
  let res = await call("/api/me/food-preferences", a.token, { kind: "allergy", term: "Peanut" });
  expect(res.status).toBe(201);
  const allergy = await J(res);
  expect(allergy).toMatchObject({ kind: "allergy", term: "kacang", severity: "strict", version: 1 });
  res = await call("/api/me/food-preferences", a.token, { kind: "allergy", term: "kacang tanah" });
  expect(res.status).toBe(200);
  expect((await J(res)).id).toBe(allergy.id);
  expect(await prisma.foodPreference.count({ where: { userId: a.id } })).toBe(1);

  // Ketidaksukaan bersifat soft.
  const dislike = await J(await call("/api/me/food-preferences", a.token, { kind: "dislike", term: "pare" }));
  expect(dislike.severity).toBe("soft");

  // Daftar milik sendiri; akun lain kosong.
  expect((await J(await call("/api/me/food-preferences", a.token))).items).toHaveLength(2);
  expect((await J(await call("/api/me/food-preferences", b.token))).items).toHaveLength(0);

  // Akun lain tidak bisa mengubah milik A.
  expect((await call(`/api/me/food-preferences/${allergy.id}`, b.token, { expectedVersion: 1, archived: true }, "PATCH")).status).toBe(404);

  // Versi usang ditolak; versi benar menaikkan versi.
  expect((await call(`/api/me/food-preferences/${dislike.id}`, a.token, { expectedVersion: 9, notes: "x" }, "PATCH")).status).toBe(409);
  const patched = await J(await call(`/api/me/food-preferences/${dislike.id}`, a.token, { expectedVersion: 1, notes: "pahit" }, "PATCH"));
  expect(patched).toMatchObject({ version: 2, notes: "pahit" });

  // Pengecekan: alergi kacang mengecualikan, tanpa kecocokan tidak berarti aman.
  const chk = await J(await call("/api/me/food-preferences/check", a.token, { items: [{ name: "Gado-gado" }, { name: "Nasi putih" }, { name: "Tumis pare" }] }));
  expect(chk.hasStrictConstraints).toBe(true);
  expect(chk.results.map((r: any) => r.status)).toEqual(["EXCLUDED", "NO_MATCH_FOUND", "WARNING"]);
  expect(chk.results[1].note).toContain("tidak diketahui");

  // Pencarian makanan menyertakan pengecekan; hideExcluded menyembunyikan yang dikecualikan.
  const food = await call("/api/me/foods", a.token, { name: "Selai kacang uji", source: "Uji", status: "user_reported", per100g: { calories: 590, carbohydrates: 20, protein: 25, fat: 50, fiber: 6 } });
  expect(food.status).toBe(201);
  const ok = await call("/api/me/foods", a.token, { name: "Selai stroberi uji", source: "Uji", status: "user_reported", per100g: { calories: 250, carbohydrates: 60, protein: 0.5, fat: 0.2, fiber: 1 } });
  expect(ok.status).toBe(201);
  let found = await J(await call("/api/me/foods/discover?q=selai", a.token));
  const statuses = Object.fromEntries(found.local.map((f: any) => [f.name, f.preferenceCheck.status]));
  expect(statuses["Selai kacang uji"]).toBe("EXCLUDED");
  expect(statuses["Selai stroberi uji"]).toBe("NO_MATCH_FOUND");
  found = await J(await call("/api/me/foods/discover?q=selai&hideExcluded=true", a.token));
  expect(found.local.map((f: any) => f.name)).toEqual(["Selai stroberi uji"]);

  // Arsip: kendala tidak lagi berlaku dan tidak tampil di daftar aktif; bisa dipulihkan.
  await call(`/api/me/food-preferences/${allergy.id}`, a.token, { expectedVersion: 1, archived: true }, "PATCH");
  expect((await J(await call("/api/me/food-preferences", a.token))).items).toHaveLength(1);
  expect((await J(await call("/api/me/food-preferences?archived=true", a.token))).items).toHaveLength(1);
  const restored = await J(await call("/api/me/food-preferences", a.token, { kind: "allergy", term: "kacang" }));
  expect(restored).toMatchObject({ id: allergy.id, archivedAt: null });
  expect(restored.version).toBeGreaterThan(2);

  // Hapus akun menghapus preferensi (cascade).
  await prisma.users.delete({ where: { id: a.id } });
  expect(await prisma.foodPreference.count({ where: { userId: a.id } })).toBe(0);
});
