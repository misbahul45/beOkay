import { describe, expect, it, mock } from "bun:test";

mock.module("../../src/features/consent/consent.service.ts", () => ({ consentService: { requireConsent: async () => {} } }));
mock.module("../../src/features/nutrition/nutrition.service.ts", () => ({ nutritionService: { searchFoods: async () => ({ items: [] }) } }));

const { createFoodVision, photoOutput } = await import("../../src/features/food-vision/food-vision.service.ts");
const { createMistralClient } = await import("../../src/features/food-vision/mistral.client.ts");
const { sniffImage } = await import("../../src/features/food-vision/image.ts");

const jpeg = { bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]), mime: "image/jpeg" as const };
const cfg = { apiKey: "k", ocrModel: "ocr-x", visionModel: "vis-x" };
const json = (b: unknown) => Promise.resolve(new Response(JSON.stringify(b), { status: 200 }));

describe("food vision", () => {
  it("sniffImage mengenali magic byte, bukan header klien", () => {
    expect(sniffImage(jpeg.bytes)).toBe("image/jpeg");
    expect(sniffImage(new Uint8Array([1, 2, 3, 4]))).toBeNull();
    expect(sniffImage(new TextEncoder().encode("<svg onload=alert(1)>"))).toBeNull();
  });

  it("label: OCR → parser → kandidat; host dan kunci dipaku, gambar dikirim sebagai data URL", async () => {
    let seen: { url: string; auth: string | null; body: any } | null = null;
    const f = (async (url: URL, init: RequestInit) => {
      seen = { url: String(url), auth: new Headers(init.headers).get("authorization"), body: JSON.parse(String(init.body)) };
      return json({ pages: [{ markdown: "Takaran saji 30 g\nEnergi 120 kkal\nProtein 6 g\nLemak total 3 g\nKarbohidrat 18 g" }] });
    }) as unknown as typeof fetch;
    const svc = createFoodVision({ mistral: createMistralClient(cfg, f) });
    const r = await svc.scanLabel("u1", jpeg);
    expect(r.status).toBe("READ");
    expect((r as any).candidate.per100g.calories).toBe(400);
    expect((r as any).candidate.source).toBe("Label kemasan (OCR)");
    expect(seen!.url).toBe("https://api.mistral.ai/v1/ocr");
    expect(seen!.auth).toBe("Bearer k");
    expect(seen!.body.model).toBe("ocr-x");
    expect(seen!.body.document.image_url.startsWith("data:image/jpeg;base64,")).toBe(true);
  });

  it("label tanpa gizi → NO_NUTRITION", async () => {
    const f = (() => json({ pages: [{ markdown: "Keripik pedas" }] })) as unknown as typeof fetch;
    const r = await createFoodVision({ mistral: createMistralClient(cfg, f) }).scanLabel("u1", jpeg);
    expect(r.status).toBe("NO_NUTRITION");
  });

  it("tanpa kunci → UNAVAILABLE/PROVIDER_NOT_CONFIGURED tanpa memanggil jaringan", async () => {
    let called = 0;
    const f = (() => { called++; return json({}); }) as unknown as typeof fetch;
    const r = await createFoodVision({ mistral: createMistralClient({ ...cfg, apiKey: undefined }, f) }).scanLabel("u1", jpeg);
    expect(r).toMatchObject({ status: "UNAVAILABLE", code: "PROVIDER_NOT_CONFIGURED" });
    expect(called).toBe(0);
  });

  it("penyedia gagal → UNAVAILABLE, bukan 500", async () => {
    const f = (() => Promise.resolve(new Response("x", { status: 503 }))) as unknown as typeof fetch;
    const r = await createFoodVision({ mistral: createMistralClient(cfg, f) }).identifyPhoto("u1", jpeg);
    expect(r).toMatchObject({ status: "UNAVAILABLE", code: "PROVIDER_UNAVAILABLE" });
  });

  it("foto: hanya nama + padanan katalog; tidak ada kalori dari model", async () => {
    const f = (() =>
      json({ choices: [{ message: { content: JSON.stringify({ isFood: true, items: [{ name: "Nasi putih", confidence: "high" }, { name: "Tempe goreng", confidence: "low", calories: 9999 }] }) } }] })) as unknown as typeof fetch;
    const search = async (_u: string, q: string) => ({ items: q === "Nasi putih" ? [{ id: "f1", name: "Nasi putih" }] : [] });
    const r: any = await createFoodVision({ mistral: createMistralClient(cfg, f), search }).identifyPhoto("u1", jpeg);
    expect(r.status).toBe("IDENTIFIED");
    expect(r.items[0].matches[0].id).toBe("f1");
    expect(r.items[1].matches).toEqual([]);
    expect(JSON.stringify(r)).not.toContain("9999");
  });

  it("foto bukan makanan → NOT_FOOD; keluaran tak sesuai skema ditolak", async () => {
    const notFood = (() => json({ choices: [{ message: { content: '{"isFood":false,"items":[]}' } }] })) as unknown as typeof fetch;
    expect((await createFoodVision({ mistral: createMistralClient(cfg, notFood) }).identifyPhoto("u1", jpeg)).status).toBe("NOT_FOOD");
    const bad = (() => json({ choices: [{ message: { content: '{"isFood":"yes"}' } }] })) as unknown as typeof fetch;
    expect(await createFoodVision({ mistral: createMistralClient(cfg, bad) }).identifyPhoto("u1", jpeg)).toMatchObject({ status: "UNAVAILABLE", code: "PROVIDER_BAD_RESPONSE" });
    expect(photoOutput.safeParse({ isFood: true, items: Array(7).fill({ name: "ab", confidence: "high" }) }).success).toBe(false);
  });

  it("batas 10 pemindaian per 10 menit per pengguna", async () => {
    const f = (() => json({ pages: [{ markdown: "x" }] })) as unknown as typeof fetch;
    let t = 0;
    const svc = createFoodVision({ mistral: createMistralClient(cfg, f), now: () => t });
    for (let i = 0; i < 10; i++) await svc.scanLabel("u1", jpeg);
    await expect(svc.scanLabel("u1", jpeg)).rejects.toMatchObject({ status: 429 });
    await svc.scanLabel("u2", jpeg); // pengguna lain tidak terpengaruh
    t = 11 * 60_000;
    await svc.scanLabel("u1", jpeg);
  });
});
