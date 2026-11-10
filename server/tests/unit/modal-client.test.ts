import { expect, test } from "bun:test";
import { allowedModalUrl, createModalClient } from "../../src/features/ml/modal.client.ts";

const SHA = "a".repeat(64);
const ok = (over: object = {}) => Response.json({ modelKey: "dish-classifier", modelVersion: "v1", artifactSha256: SHA, predictions: [{ label: "Rendang", probability: 0.8 }, { label: "Soto", probability: 0.15 }], ...over });
const URL_OK = "https://beokay--dish.modal.run";
const img = new Uint8Array([1, 2, 3]);

function fake(handler: (n: number) => Response | Promise<Response>) {
  const calls: { url: string; init: RequestInit }[] = [];
  const impl = (async (url: string | URL, init: RequestInit) => { calls.push({ url: String(url), init }); return handler(calls.length); }) as unknown as typeof fetch;
  return { calls, impl };
}

test("hanya https://*.modal.run tanpa kredensial yang diterima", () => {
  expect(allowedModalUrl(URL_OK)?.hostname).toBe("beokay--dish.modal.run");
  for (const bad of ["http://x.modal.run", "https://evil.example/x", "https://u:p@x.modal.run", "https://modal.run.evil.com", "bukan url", undefined, ""]) expect(allowedModalUrl(bad as string)).toBeNull();
});

test("tanpa konfigurasi tidak ada panggilan jaringan", async () => {
  const f = fake(() => ok());
  const c = createModalClient({ url: undefined, token: "t" }, { fetchImpl: f.impl });
  expect(c.configured).toBe(false);
  expect(await c.predict(img)).toMatchObject({ ok: false, code: "NOT_CONFIGURED" });
  expect(createModalClient({ url: "https://evil.example", token: "t" }).configured).toBe(false);
  expect(f.calls).toHaveLength(0);
});

test("permintaan membawa bearer di header, tanpa redirect, hanya gambar (tanpa identitas); balasan valid diterima", async () => {
  const f = fake(() => ok());
  const r = await createModalClient({ url: URL_OK, token: "tok-uji" }, { fetchImpl: f.impl }).predict(img, 2);
  expect(r).toMatchObject({ ok: true, data: { modelVersion: "v1" } });
  const call = f.calls[0]!;
  expect(call.url).toBe(URL_OK + "/");
  expect((call.init.headers as Record<string, string>).authorization).toBe("Bearer tok-uji");
  expect(call.init.redirect).toBe("error");
  const body = JSON.parse(String(call.init.body));
  expect(Object.keys(body).sort()).toEqual(["imageBase64", "topK"]);
  expect(String(call.url)).not.toContain("tok-uji");
});

test("balasan tidak valid ditolak: skema salah, probabilitas > 1, jumlah > 1, hash salah, JSON rusak", async () => {
  const bad = async (resp: () => Response) => createModalClient({ url: URL_OK, token: "t" }, { fetchImpl: fake(resp).impl }).predict(img);
  expect(await bad(() => Response.json({ nope: 1 }))).toMatchObject({ ok: false, code: "INVALID_RESPONSE" });
  expect(await bad(() => ok({ predictions: [{ label: "x", probability: 1.4 }] }))).toMatchObject({ ok: false, code: "INVALID_RESPONSE" });
  expect(await bad(() => ok({ predictions: [{ label: "a", probability: 0.7 }, { label: "b", probability: 0.7 }] }))).toMatchObject({ ok: false, code: "INVALID_RESPONSE" });
  expect(await bad(() => ok({ artifactSha256: "xyz" }))).toMatchObject({ ok: false, code: "INVALID_RESPONSE" });
  expect(await bad(() => new Response("bukan json"))).toMatchObject({ ok: false, code: "INVALID_RESPONSE" });
  expect(await bad(() => ok({ predictions: [] }))).toMatchObject({ ok: false, code: "INVALID_RESPONSE" });
});

test("401/403 dan 5xx = UNAVAILABLE; satu coba-ulang untuk 5xx dan jaringan; tidak untuk 4xx", async () => {
  const a = fake(() => new Response("x", { status: 401 }));
  expect(await createModalClient({ url: URL_OK, token: "t" }, { fetchImpl: a.impl }).predict(img)).toMatchObject({ ok: false, code: "UNAVAILABLE" });
  expect(a.calls).toHaveLength(1);
  const b = fake((n) => (n === 1 ? new Response("x", { status: 503 }) : ok()));
  expect(await createModalClient({ url: URL_OK, token: "t" }, { fetchImpl: b.impl }).predict(img)).toMatchObject({ ok: true });
  expect(b.calls).toHaveLength(2);
  const c = fake(() => { throw new Error("net"); });
  expect(await createModalClient({ url: URL_OK, token: "t" }, { fetchImpl: c.impl }).predict(img)).toMatchObject({ ok: false, code: "UNAVAILABLE" });
  expect(c.calls).toHaveLength(2);
});

test("timeout dilaporkan sebagai TIMEOUT", async () => {
  const f = fake(() => { const e = new Error("t"); e.name = "TimeoutError"; throw e; });
  expect(await createModalClient({ url: URL_OK, token: "t" }, { fetchImpl: f.impl }).predict(img)).toMatchObject({ ok: false, code: "TIMEOUT" });
});

test("circuit breaker: 3 gagal beruntun membuka sirkuit tanpa memanggil jaringan; setengah-terbuka setelah jeda; sukses menutup", async () => {
  let t = 1_000_000;
  let healthy = false;
  const f = fake(() => (healthy ? ok() : new Response("x", { status: 400 })));
  const c = createModalClient({ url: URL_OK, token: "t", openMs: 60_000 }, { fetchImpl: f.impl, now: () => t });
  for (let i = 0; i < 3; i++) expect((await c.predict(img)).ok).toBe(false);
  const callsAfterOpen = f.calls.length;
  expect(c.circuitOpen).toBe(true);
  expect(await c.predict(img)).toMatchObject({ ok: false, code: "CIRCUIT_OPEN" });
  expect(f.calls.length).toBe(callsAfterOpen); // tidak ada panggilan saat terbuka
  t += 61_000;
  healthy = true;
  expect(await c.predict(img)).toMatchObject({ ok: true }); // percobaan setengah-terbuka
  expect(c.circuitOpen).toBe(false);
  expect(await c.predict(img)).toMatchObject({ ok: true });
});
