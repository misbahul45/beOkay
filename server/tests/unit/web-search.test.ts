import { expect, mock, test } from "bun:test";
import { createWebSearchClient, safeResultUrl } from "../../src/features/food-discovery/web-search.client.ts";

mock.module("../../src/features/nutrition/nutrition.service.ts", () => ({ nutritionService: { searchFoods: async () => ({ items: [] }) } }));
mock.module("../../src/features/food-preferences/food-preferences.service.ts", () => ({ foodPreferencesService: { activeFor: async () => [] } }));
mock.module("../../src/features/consent/consent.service.ts", () => ({ consentService: { requireConsent: async () => {} } }));
const { createFoodDiscovery } = await import("../../src/features/food-discovery/food-discovery.service.ts");

const reply = (body: unknown, status = 200) => (async () => new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;

test("tautan hasil: hanya https publik tanpa kredensial, port, atau host lokal/IP", () => {
  expect(safeResultUrl("https://id.wikipedia.org/wiki/Tempe")?.hostname).toBe("id.wikipedia.org");
  for (const bad of ["http://a.com", "https://user:pw@a.com", "https://a.com:8443/x", "https://localhost/x", "https://127.0.0.1/x", "https://10.0.0.5/x", "https://intranet/x", "https://svc.internal/x", "javascript:alert(1)", "ftp://a.com", 5, null, "x".repeat(600)])
    expect(safeResultUrl(bad as unknown)).toBeNull();
});

test("tanpa kunci tidak ada panggilan jaringan", async () => {
  let called = 0;
  const c = createWebSearchClient(undefined, (async () => { called++; return new Response("{}"); }) as unknown as typeof fetch);
  expect(c.configured).toBe(false);
  await expect(c.search("tempe")).rejects.toMatchObject({ code: "PROVIDER_NOT_CONFIGURED" });
  expect(called).toBe(0);
});

test("hasil dibersihkan: tag HTML dibuang, URL berbahaya dibuang, ditandai tidak ditinjau dan bukan data gizi, kunci hanya di header", async () => {
  let seen: { url?: string; init?: RequestInit } = {};
  const fetchImpl = (async (url: URL, init: RequestInit) => {
    seen = { url: String(url), init };
    return new Response(JSON.stringify({ query: "tempe", results: [
      { title: "<strong>Tempe</strong> &amp; gizinya", url: "https://id.wikipedia.org/wiki/Tempe", content: "<b>Tempe</b> kaya protein.", score: 0.9 },
      { title: "Jahat", url: "http://evil.example/x", content: "x" },
      { title: "Lokal", url: "https://localhost/x", content: "x" },
      { title: 5, url: "https://a.example.com/x" },
    ] }));
  }) as unknown as typeof fetch;
  const key = `tvly-${crypto.randomUUID()}`;
  const items = await createWebSearchClient(key, fetchImpl).search("tempe");
  expect(items).toEqual([{ title: "Tempe & gizinya", url: "https://id.wikipedia.org/wiki/Tempe", host: "id.wikipedia.org", snippet: "Tempe kaya protein.", reviewed: false, usableForNutrition: false }]);
  expect(seen.url).toBe("https://api.tavily.com/search");
  expect(seen.init!.method).toBe("POST");
  expect(seen.init!.redirect).toBe("error");
  const headers = seen.init!.headers as Record<string, string>;
  expect(headers.authorization).toBe(`Bearer ${key}`);
  expect(headers["content-type"]).toBe("application/json");
  const sent = JSON.parse(String(seen.init!.body));
  expect(sent).toMatchObject({ query: "tempe", max_results: 5, search_depth: "basic", country: "indonesia", include_raw_content: false, include_answer: false });
  expect(JSON.stringify(sent)).not.toContain(key);
});

test("kueri dipotong 120 karakter dan jumlah hasil dibatasi 8", async () => {
  let sent: { query?: string; max_results?: number } = {};
  const fetchImpl = (async (_url: URL, init: RequestInit) => {
    sent = JSON.parse(String(init.body));
    return new Response(JSON.stringify({ results: [] }));
  }) as unknown as typeof fetch;
  await createWebSearchClient("k", fetchImpl).search("a".repeat(300), 20);
  expect(sent.query).toHaveLength(120);
  expect(sent.max_results).toBe(8);
});

test("balasan rusak dan galat jaringan menjadi ProviderError", async () => {
  await expect(createWebSearchClient("k", reply({ nope: 1 })).search("a")).rejects.toMatchObject({ code: "PROVIDER_BAD_RESPONSE" });
  await expect(createWebSearchClient("k", reply({}, 500)).search("a")).rejects.toMatchObject({ code: "PROVIDER_UNAVAILABLE" });
  await expect(createWebSearchClient("k", (async () => { throw new Error("net"); }) as unknown as typeof fetch).search("a")).rejects.toMatchObject({ code: "PROVIDER_UNAVAILABLE" });
});

test("layanan: nonaktif tanpa kunci, dibatasi laju bersama sumber luar, kegagalan penyedia tidak melempar", async () => {
  const off = { search: async () => [], byBarcode: async () => null };
  const usda = { configured: false, search: async () => [] };
  const none = createFoodDiscovery({ off, usda, web: createWebSearchClient(undefined) });
  expect(await none.web("u", "tempe")).toEqual({ status: "NOT_CONFIGURED", items: [] });

  const down = createFoodDiscovery({ off, usda, web: createWebSearchClient("k", reply({}, 503)) });
  expect(await down.web("u", "tempe")).toMatchObject({ status: "UNAVAILABLE", items: [], code: "PROVIDER_UNAVAILABLE" });

  const ok = createFoodDiscovery({ off, usda, web: createWebSearchClient("k", reply({ results: [] })) });
  for (let i = 0; i < 20; i++) await ok.web("u", "tempe");
  await expect(ok.web("u", "tempe")).rejects.toMatchObject({ status: 429 });
});
