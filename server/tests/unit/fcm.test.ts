import { createVerify, generateKeyPairSync } from "node:crypto";
import { expect, test } from "bun:test";
import { classifyFcmError, createFcmClient, parseServiceAccount } from "../../src/features/push/fcm.client.ts";

// Kunci dibangkitkan per eksekusi; tidak ada rahasia sebagai literal.
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const account = (over: object = {}) => JSON.stringify({ client_email: "svc@example-project.iam.gserviceaccount.com", private_key: pem, token_uri: "https://oauth2.googleapis.com/token", ...over });
const msg = { token: "t".repeat(40), title: "Pengingat beOkay", body: "Buka beOkay untuk mencatat.", data: { type: "reminder" } };

type Call = { url: string; init: RequestInit };
function fakeFetch(handlers: { fcm?: () => Response; token?: () => Response } = {}) {
  const calls: Call[] = [];
  const impl = (async (url: string | URL, init: RequestInit) => {
    calls.push({ url: String(url), init });
    if (String(url).startsWith("https://oauth2.googleapis.com/token")) return handlers.token ? handlers.token() : Response.json({ access_token: "at-" + calls.length, expires_in: 3600 });
    return handlers.fcm ? handlers.fcm() : Response.json({ name: "projects/p/messages/abc123" });
  }) as unknown as typeof fetch;
  return { calls, impl };
}

test("tanpa konfigurasi tidak ada panggilan jaringan", async () => {
  const f = fakeFetch();
  const c = createFcmClient({ projectId: undefined, serviceAccountJson: undefined }, { fetchImpl: f.impl });
  expect(c.configured).toBe(false);
  expect(await c.send(msg)).toMatchObject({ status: "failed", errorCode: "FCM_NOT_CONFIGURED", shouldDeactivate: false });
  expect(f.calls).toHaveLength(0);
  expect(createFcmClient({ projectId: "p", serviceAccountJson: "bukan json" }).configured).toBe(false);
});

test("JSON akun layanan diterima mentah maupun base64; yang rusak ditolak tanpa mencetak isinya", () => {
  expect(parseServiceAccount(account())?.client_email).toContain("@");
  expect(parseServiceAccount(Buffer.from(account()).toString("base64"))?.client_email).toContain("@");
  expect(parseServiceAccount(JSON.stringify({ client_email: "x", private_key: "bukan kunci" }))).toBeNull();
  expect(parseServiceAccount("")).toBeNull();
});

test("JWT ditandatangani RS256 dengan klaim yang benar; pengiriman memakai host tetap dan konten generik", async () => {
  const f = fakeFetch();
  const c = createFcmClient({ projectId: "proj-1", serviceAccountJson: account() }, { fetchImpl: f.impl, now: () => 1_800_000_000_000 });
  const r = await c.send(msg);
  expect(r).toEqual({ status: "sent", providerMessageId: "projects/p/messages/abc123", httpStatus: 200, shouldDeactivate: false });

  const form = new URLSearchParams(String(f.calls[0]!.init.body));
  expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
  const [h, p, s] = form.get("assertion")!.split(".") as [string, string, string];
  expect(JSON.parse(Buffer.from(h, "base64url").toString())).toEqual({ alg: "RS256", typ: "JWT" });
  const claims = JSON.parse(Buffer.from(p, "base64url").toString());
  expect(claims).toMatchObject({ aud: "https://oauth2.googleapis.com/token", scope: "https://www.googleapis.com/auth/firebase.messaging", iat: 1_800_000_000, exp: 1_800_003_600 });
  expect(createVerify("RSA-SHA256").update(`${h}.${p}`).verify(publicKey, Buffer.from(s, "base64url"))).toBe(true);

  const send = f.calls[1]!;
  expect(send.url).toBe("https://fcm.googleapis.com/v1/projects/proj-1/messages:send");
  expect((send.init.headers as Record<string, string>).authorization).toBe("Bearer at-1");
  expect(send.init.redirect).toBe("error");
  const body = JSON.parse(String(send.init.body));
  expect(body.message.notification).toEqual({ title: "Pengingat beOkay", body: "Buka beOkay untuk mencatat." });
  expect(body.message.android.notification).toMatchObject({ channel_id: "beokay_reminders", visibility: "PRIVATE" });
  expect(body.validate_only).toBeUndefined();
  expect(JSON.stringify(f.calls)).not.toContain("PRIVATE KEY"); // kunci tidak pernah dikirim
});

test("token akses di-cache antar pengiriman dan diperbarui setelah kedaluwarsa", async () => {
  const f = fakeFetch();
  let t = 1_800_000_000_000;
  const c = createFcmClient({ projectId: "p", serviceAccountJson: account() }, { fetchImpl: f.impl, now: () => t });
  await c.send(msg);
  await c.send(msg);
  expect(f.calls.filter((x) => x.url.includes("oauth2"))).toHaveLength(1);
  t += 3_700_000;
  await c.send(msg);
  expect(f.calls.filter((x) => x.url.includes("oauth2"))).toHaveLength(2);
});

test("validate_only dikirim bila diminta", async () => {
  const f = fakeFetch();
  await createFcmClient({ projectId: "p", serviceAccountJson: account() }, { fetchImpl: f.impl }).send(msg, { validateOnly: true });
  expect(JSON.parse(String(f.calls[1]!.init.body)).validate_only).toBe(true);
});

test("klasifikasi galat: UNREGISTERED/NOT_FOUND/SENDER_ID_MISMATCH menonaktifkan; INVALID_ARGUMENT dan 5xx tidak", async () => {
  const mk = (status: number, error: object) => fakeFetch({ fcm: () => Response.json({ error }, { status }) });
  const run = async (status: number, error: object) => createFcmClient({ projectId: "p", serviceAccountJson: account() }, { fetchImpl: mk(status, error).impl }).send(msg);
  expect(await run(404, { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] })).toMatchObject({ status: "invalid_token", errorCode: "UNREGISTERED", shouldDeactivate: true });
  expect(await run(403, { status: "PERMISSION_DENIED", details: [{ errorCode: "SENDER_ID_MISMATCH" }] })).toMatchObject({ status: "invalid_token", shouldDeactivate: true });
  expect(await run(400, { status: "INVALID_ARGUMENT" })).toMatchObject({ status: "failed", errorCode: "INVALID_ARGUMENT", shouldDeactivate: false });
  expect(await run(503, { status: "UNAVAILABLE" })).toMatchObject({ status: "failed", errorCode: "UNAVAILABLE", shouldDeactivate: false });
  expect(classifyFcmError(500, undefined)).toEqual({ code: "HTTP_500", invalidToken: false });
});

test("401 menghapus cache token sehingga pengiriman berikutnya mengautentikasi ulang", async () => {
  let n = 0;
  const f = fakeFetch({ fcm: () => (++n === 1 ? Response.json({ error: { status: "UNAUTHENTICATED" } }, { status: 401 }) : Response.json({ name: "ok" })) });
  const c = createFcmClient({ projectId: "p", serviceAccountJson: account() }, { fetchImpl: f.impl });
  expect((await c.send(msg)).status).toBe("failed");
  expect((await c.send(msg)).status).toBe("sent");
  expect(f.calls.filter((x) => x.url.includes("oauth2"))).toHaveLength(2);
});

test("token_uri selain host Google ditolak (tidak mengirim assertion ke host lain) dan galat jaringan menjadi failed", async () => {
  const f = fakeFetch();
  const evil = await createFcmClient({ projectId: "p", serviceAccountJson: account({ token_uri: "https://evil.example/token" }) }, { fetchImpl: f.impl }).send(msg);
  expect(evil).toMatchObject({ status: "failed", errorCode: "FCM_TOKEN_URI_NOT_ALLOWED" });
  expect(f.calls).toHaveLength(0);
  const down = await createFcmClient({ projectId: "p", serviceAccountJson: account() }, { fetchImpl: (async () => { throw new Error("net"); }) as unknown as typeof fetch }).send(msg);
  expect(down).toMatchObject({ status: "failed", errorCode: "NETWORK_ERROR", shouldDeactivate: false });
});
