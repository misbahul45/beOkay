import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { EMBEDDING_DIMENSIONS, toVectorLiteral } from "../../src/features/food-reference/embedding.client.ts";
import { createReferenceService } from "../../src/features/food-reference/reference.service.ts";
import { ProviderError } from "../../src/features/food-discovery/food-candidate.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(consent = true) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `fr-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (consent) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing"] });
  }
  return { id, token };
}

/** Vektor satu-panas pada dimensi `axis`, dengan sedikit komponen pada `blend` agar kemiripan dapat diatur. */
const axis = (i: number, blend?: { j: number; w: number }) => {
  const v = Array.from({ length: EMBEDDING_DIMENSIONS }, () => 0);
  v[i] = 1;
  if (blend) v[blend.j] = blend.w;
  return v;
};
const fixtures = [
  { code: "ZZTEST01", name: "Tempe uji goreng", status: "verified_auto", cal: 300, axis: 0 },
  { code: "ZZTEST02", name: "Tahu uji kukus", status: "verified_auto", cal: 80, axis: 1 },
  { code: "ZZTEST03", name: "Bayam uji rebus", status: "verified_auto", cal: 25, axis: 2 },
  { code: "ZZTEST04", name: "Tempe uji salah baca", status: "needs_review", cal: 999, axis: 0 },
];
beforeAll(async () => {
  for (const f of fixtures) {
    await prisma.$executeRawUnsafe(
      `INSERT INTO food_reference (code,name,name_normalized,source,source_version,status,calories,protein,fat,carbohydrates,embedding,embedding_model,updated_at)
       VALUES ('${f.code}','${f.name}','${f.name.toLowerCase()}','TKPI','TKPI 2017','${f.status}',${f.status === "verified_auto" ? f.cal : "NULL"},5,5,10,'${toVectorLiteral(axis(f.axis))}'::vector,'fake',now())`,
    );
  }
});
afterAll(async () => {
  await prisma.$executeRawUnsafe(`DELETE FROM food_reference WHERE code LIKE 'ZZTEST%'`);
  await prisma.users.deleteMany({ where: { id: { in: users } } });
});

const fake = (vec: number[] | Error) => ({ configured: true, embed: async () => { if (vec instanceof Error) throw vec; return [vec]; } });

test("leksikal: menemukan baris verified_auto, tidak pernah needs_review, nilai kosong tetap null", async () => {
  const svc = createReferenceService({ embedder: { configured: false, embed: async () => [] } });
  const r = await svc.search("tempe uji");
  expect(r.status).toBe("LEXICAL_ONLY");
  const names = r.items.map((i) => i.name);
  expect(names).toContain("Tempe uji goreng");
  expect(names).not.toContain("Tempe uji salah baca"); // needs_review dikecualikan
  expect(r.items[0]!.provenance).toBe("Tabel Komposisi Pangan Indonesia");
  expect(r.items[0]!.per100g.fiber).toBeNull();
  expect(r.items[0]!.matchedBy).toEqual(["lexical"]);
  expect((await svc.search("a")).items).toEqual([]); // terlalu pendek
});

test("semantik: kueri tanpa kata yang sama tetap menemukan baris terdekat; similarity rendah dibuang", async () => {
  const near = createReferenceService({ embedder: fake(axis(1, { j: 5, w: 0.1 })) }); // cos ≈ 0,995 ke "Tahu uji kukus"
  const r = await near.search("makanan kedelai putih");
  expect(r.status).toBe("OK");
  expect(r.items[0]).toMatchObject({ name: "Tahu uji kukus", matchedBy: ["semantic"] });
  expect(r.items.every((i) => i.name.startsWith("Tahu") || i.matchedBy.includes("semantic"))).toBe(true);

  const far = createReferenceService({ embedder: fake(axis(9)) }); // ortogonal ke semua fixture → similarity 0
  const none = await far.search("zzzz tidak ada");
  expect(none.items.filter((i) => i.code.startsWith("ZZTEST"))).toEqual([]);
});

test("fusi: kata cocok + semantik mengangkat baris yang sama ke puncak dengan dua penanda", async () => {
  const svc = createReferenceService({ embedder: fake(axis(0, { j: 7, w: 0.05 })) });
  const r = await svc.search("tempe uji goreng");
  expect(r.items[0]).toMatchObject({ name: "Tempe uji goreng", matchedBy: ["lexical", "semantic"] });
  expect(r.items.map((i) => i.name)).not.toContain("Tempe uji salah baca");
});

test("penyedia embedding gagal: kembali ke leksikal tanpa error", async () => {
  const svc = createReferenceService({ embedder: fake(new ProviderError("PROVIDER_UNAVAILABLE", "x")) });
  const r = await svc.search("bayam uji");
  expect(r.status).toBe("LEXICAL_ONLY");
  expect(r.items[0]!.name).toBe("Bayam uji rebus");
});

test("CHECK database: verified_auto tanpa kalori ditolak; nilai di luar rentang ditolak", async () => {
  const bad = async (sql: string) => { try { await prisma.$executeRawUnsafe(sql); return false; } catch { return true; } };
  expect(await bad(`INSERT INTO food_reference (code,name,name_normalized,source,source_version,status,protein,fat,carbohydrates,updated_at) VALUES ('ZZTESTX1','x','x','TKPI','v','verified_auto',1,1,1,now())`)).toBe(true);
  expect(await bad(`INSERT INTO food_reference (code,name,name_normalized,source,source_version,status,calories,protein,fat,carbohydrates,updated_at) VALUES ('ZZTESTX2','x','x','TKPI','v','needs_review',9999,1,1,1,now())`)).toBe(true);
  expect(await bad(`INSERT INTO food_reference (code,name,name_normalized,source,source_version,status,updated_at) VALUES ('ZZTESTX3','x','x','TKPI','v','bebas',now())`)).toBe(true);
});

test("API: butuh login dan consent, validasi kueri, dan hasilnya membawa provenans", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), none = await actor(false);
  expect((await call("/api/me/foods/reference?q=tempe")).status).toBe(401);
  expect((await call("/api/me/foods/reference?q=tempe", none.token)).status).toBe(403);
  expect((await call("/api/me/foods/reference?q=t", a.token)).status).toBe(400);
  const res = await call("/api/me/foods/reference?q=tempe%20uji", a.token);
  expect(res.status).toBe(200);
  const body = (await res.json()) as any;
  expect(body.status).toBe("LEXICAL_ONLY"); // server uji tidak punya kunci embedding
  expect(body.items.map((i: any) => i.name)).toContain("Tempe uji goreng");
  expect(body.items.every((i: any) => i.verification === "verified_auto")).toBe(true);
  // Pencarian makanan terpadu menyertakan referensi dan pengecekan preferensi.
  const disc = (await (await call("/api/me/foods/discover?q=tempe%20uji", a.token)).json()) as any;
  expect(disc.reference.items.map((i: any) => i.name)).toContain("Tempe uji goreng");
  expect(disc.reference.items[0].preferenceCheck.status).toBe("NO_MATCH_FOUND");
});
