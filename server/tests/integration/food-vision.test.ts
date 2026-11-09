import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const raw = (path: string, token: string | undefined, body: Uint8Array | undefined, type = "image/jpeg") =>
  fetch(api + path, { method: "POST", headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), "content-type": type }, body });
const call = (path: string, token?: string, body?: object) =>
  fetch(api + path, { method: body ? "POST" : "GET", headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(consent = true) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `vis-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (consent) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
  }
  return { token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70, 0]);

test("Image scan endpoints: auth, consent, input limits, and no provider key means no network call", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), none = await actor(false);
  for (const p of ["/api/me/foods/scan/label", "/api/me/foods/scan/photo"]) {
    expect((await raw(p, undefined, JPEG)).status).toBe(401);
    expect((await raw(p, none.token, JPEG)).status).toBe(403); // tanpa consent, gambar tidak diproses
    expect((await raw(p, a.token, new Uint8Array(0))).status).toBe(400);
    const notImage = await raw(p, a.token, new TextEncoder().encode("<svg onload=alert(1)>"), "image/jpeg");
    expect(notImage.status).toBe(400);
    expect(((await notImage.json()) as any).error.code).toBe("IMAGE_UNSUPPORTED");
    const big = await raw(p, a.token, new Uint8Array(1_600_000).fill(0xff));
    expect(big.status).toBe(413);
    // Kunci penyedia tidak ada di stack uji → hasil terkendali, bukan 500.
    const ok = await raw(p, a.token, JPEG);
    expect(ok.status).toBe(200);
    expect(await ok.json()).toMatchObject({ status: "UNAVAILABLE", code: "PROVIDER_NOT_CONFIGURED" });
  }
});
