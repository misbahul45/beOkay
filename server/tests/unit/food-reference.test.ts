import { expect, test } from "bun:test";
import { reciprocalRankFusion, sanitizeForStorage, toReferenceFood } from "../../src/features/food-reference/reference.model.ts";
import { createEmbeddingClient, EMBEDDING_DIMENSIONS, toVectorLiteral } from "../../src/features/food-reference/embedding.client.ts";

const vec = (n = EMBEDDING_DIMENSIONS, v = 0.1) => Array.from({ length: n }, () => v);
const okFetch = (n: number, over: Partial<{ dims: number; status: number; body: string }> = {}) =>
  (async () =>
    new Response(over.body ?? JSON.stringify({ data: Array.from({ length: n }, (_, i) => ({ index: n - 1 - i, embedding: vec(over.dims ?? EMBEDDING_DIMENSIONS, i) })) }), { status: over.status ?? 200 })) as unknown as typeof fetch;

test("RRF: item yang muncul di dua daftar naik, urutan stabil, label sumber kecocokan benar", () => {
  const r = reciprocalRankFusion(
    [
      { name: "lexical", items: [{ id: "a" }, { id: "b" }, { id: "c" }] },
      { name: "semantic", items: [{ id: "c" }, { id: "d" }] },
    ],
    3,
  );
  expect(r.map((x) => x.id)).toEqual(["c", "a", "b"]); // b dan d seri (peringkat kedua di daftar masing-masing): urutan id menentukan
  expect(r[0]!.matchedBy).toEqual(["lexical", "semantic"]);
  expect(reciprocalRankFusion([{ name: "x", items: [] }], 5)).toEqual([]);
});

test("sanitasi: nilai di luar rentang dikosongkan dan baris turun menjadi needs_review", () => {
  const clean = sanitizeForStorage({ name: "  Baris   aneh ", status: "verified_auto", flags: [], per100g: { water: 10, calories: 1200, protein: 5, fat: 5, carbohydrates: 5, fiber: null, ash: 1 } });
  expect(clean.per100g.calories).toBeNull();
  expect(clean.status).toBe("needs_review");
  expect(clean.flags).toContain("VALUE_DROPPED_CALORIES");
  expect(clean.name).toBe("Baris aneh");
  const good = sanitizeForStorage({ name: "Nasi", status: "verified_auto", flags: ["COLUMN_COUNT_24"], per100g: { water: 60, calories: 180, protein: 3, fat: 0.3, carbohydrates: 40, fiber: 0.2, ash: 0.5 } });
  expect(good.status).toBe("verified_auto");
  expect(good.flags).toEqual(["COLUMN_COUNT_24"]);
});

test("sanitasi: verified_auto tanpa empat makro inti diturunkan", () => {
  expect(sanitizeForStorage({ name: "X", status: "verified_auto", flags: [], per100g: { water: null, calories: 100, protein: null, fat: 1, carbohydrates: 1, fiber: null, ash: null } }).status).toBe("needs_review");
});

test("toReferenceFood: provenans jelas dan kelengkapan dihitung; nilai kosong tetap null", () => {
  const f = toReferenceFood({ id: "1", code: "AP001", name: "Nasi", sourceRef: "KZGMI-2001", page: 30, chapter: "4.1", water: 60, calories: 180, protein: 3, fat: 0.3, carbohydrates: 40, fiber: null, ash: 0.5 });
  expect(f.provenance).toBe("Tabel Komposisi Pangan Indonesia");
  expect(f.verification).toBe("verified_auto");
  expect(f.completeness).toBe("PARTIAL");
  expect(f.per100g.fiber).toBeNull();
});

test("embedding client: tanpa kunci tidak memanggil jaringan", async () => {
  let called = 0;
  const c = createEmbeddingClient({ apiKey: undefined, model: "mistral-embed" }, (async () => { called++; return new Response("{}"); }) as unknown as typeof fetch);
  expect(c.configured).toBe(false);
  await expect(c.embed(["a"])).rejects.toMatchObject({ code: "PROVIDER_NOT_CONFIGURED" });
  expect(called).toBe(0);
});

test("embedding client: urutan mengikuti index, dimensi/NaN/status/JSON salah ditolak, kunci hanya di header", async () => {
  let seen: { url?: string; init?: RequestInit } = {};
  const spy = (async (url: URL, init: RequestInit) => { seen = { url: String(url), init }; return okFetch(2)(url, init); }) as unknown as typeof fetch;
  const c = createEmbeddingClient({ apiKey: "k-test", model: "mistral-embed" }, spy);
  const out = await c.embed(["a", "b"]);
  expect(out).toHaveLength(2);
  expect(out[0]![0]).toBe(1); // fixture membalik urutan; hasil harus diurutkan menurut index
  expect(seen.url).toBe("https://api.mistral.ai/v1/embeddings");
  expect(seen.url).not.toContain("k-test");
  expect((seen.init!.headers as Record<string, string>).authorization).toBe("Bearer k-test");
  expect(seen.init!.redirect).toBe("error");

  const bad = (over: Parameters<typeof okFetch>[1]) => createEmbeddingClient({ apiKey: "k", model: "m" }, okFetch(1, over)).embed(["a"]);
  await expect(bad({ dims: 10 })).rejects.toMatchObject({ code: "PROVIDER_BAD_RESPONSE" });
  await expect(bad({ status: 500 })).rejects.toMatchObject({ code: "PROVIDER_UNAVAILABLE" });
  await expect(bad({ body: "bukan json" })).rejects.toMatchObject({ code: "PROVIDER_BAD_RESPONSE" });
  await expect(createEmbeddingClient({ apiKey: "k", model: "m" }, okFetch(1)).embed(["a", "b"])).rejects.toMatchObject({ code: "PROVIDER_BAD_RESPONSE" }); // jumlah tak cocok
  await expect(createEmbeddingClient({ apiKey: "k", model: "m" }, okFetch(1)).embed(Array.from({ length: 65 }, () => "x"))).rejects.toBeDefined();
});

test("literal vektor menolak panjang salah dan nilai tak hingga", () => {
  expect(toVectorLiteral(vec()).startsWith("[0.1,0.1")).toBe(true);
  expect(() => toVectorLiteral(vec(3))).toThrow();
  expect(() => toVectorLiteral([...vec(EMBEDDING_DIMENSIONS - 1), NaN])).toThrow();
});
