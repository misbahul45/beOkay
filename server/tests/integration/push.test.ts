import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { dispatchDueReminders } from "../../src/features/push/push-dispatcher.ts";
import type { PushMessage, PushReceipt } from "../../src/features/push/fcm.client.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor(consent = true) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `pu-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  if (consent) {
    const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
    await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing"] });
    await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  }
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;
const tok = (c = "a") => `${c}`.repeat(30) + crypto.randomUUID();

test("Perangkat push: daftar, token tidak bocor, idempoten, pindah akun, batas, cabut, consent, isolasi", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor(), none = await actor(false);
  expect((await call("/api/me/push-devices")).status).toBe(401);
  expect((await call("/api/me/push-devices", none.token)).status).toBe(403);
  expect((await call("/api/me/push-devices", a.token, { token: "pendek", platform: "android" })).status).toBe(400);
  expect((await call("/api/me/push-devices", a.token, { token: tok(), platform: "windows" })).status).toBe(400);
  expect((await call("/api/me/push-devices", a.token, { token: tok(), platform: "android", extra: 1 })).status).toBe(400);

  const t1 = tok("x");
  let res = await call("/api/me/push-devices", a.token, { token: t1, platform: "android", appVersion: "1.0.0" });
  expect(res.status).toBe(201);
  const d1 = await J(res);
  expect(d1).toMatchObject({ platform: "android", active: true, tokenHint: `…${t1.slice(-6)}` });
  expect(JSON.stringify(d1)).not.toContain(t1); // token utuh tidak dikembalikan
  res = await call("/api/me/push-devices", a.token, { token: t1, platform: "android" });
  expect(res.status).toBe(200); // idempoten
  expect((await J(res)).id).toBe(d1.id);
  expect(await prisma.pushDevice.count({ where: { userId: a.id } })).toBe(1);

  // Isolasi: akun lain tidak melihat atau mencabut perangkat A.
  expect((await J(await call("/api/me/push-devices", b.token))).items).toHaveLength(0);
  expect((await call(`/api/me/push-devices/${d1.id}`, b.token, undefined, "DELETE")).status).toBe(404);

  // Perangkat yang sama berpindah akun: token menjadi milik akun terakhir.
  res = await call("/api/me/push-devices", b.token, { token: t1, platform: "android" });
  expect(res.status).toBe(200);
  expect((await J(await call("/api/me/push-devices", a.token))).items).toHaveLength(0);
  expect((await J(await call("/api/me/push-devices", b.token))).items).toHaveLength(1);

  // Batas 5 perangkat aktif: yang terlama dinonaktifkan.
  for (let i = 0; i < 5; i++) expect((await call("/api/me/push-devices", a.token, { token: tok("k"), platform: "ios" })).status).toBe(201);
  expect((await J(await call("/api/me/push-devices", a.token))).items).toHaveLength(5);

  // Mencabut menghapus token dari basis data, dan tetap boleh tanpa consent.
  const mine = (await J(await call("/api/me/push-devices", a.token))).items[0];
  expect((await call(`/api/me/push-devices/${mine.id}`, a.token, undefined, "DELETE")).status).toBe(200);
  expect(await prisma.pushDevice.count({ where: { id: mine.id } })).toBe(0);
  expect((await call(`/api/me/push-devices/${mine.id}`, a.token, undefined, "DELETE")).status).toBe(404);
});

/** Pengirim palsu yang menyimpan pesan. */
function sender(result: (m: PushMessage) => PushReceipt = () => ({ status: "sent", providerMessageId: "m1", shouldDeactivate: false })) {
  const sent: PushMessage[] = [];
  return { sent, configured: true, async send(m: PushMessage) { sent.push(m); return result(m); } };
}
const hhmm = (d: Date) => new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Jakarta", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d);
async function withReminder(userId: string, at: Date, title = "Rahasia Metformin pagi") {
  return prisma.reminder.create({ data: { userId, kind: "medication", title, localTime: hhmm(at), daysOfWeek: [1, 2, 3, 4, 5, 6, 7] } });
}

test("Pengirim: mengirim pengingat yang jatuh tempo sekali saja, dengan isi generik, ke semua perangkat aktif", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor();
  const now = new Date();
  const due = new Date(now.getTime() - 60_000); // 1 menit lalu
  const r = await withReminder(a.id, due);
  const d1 = await prisma.pushDevice.create({ data: { userId: a.id, token: tok("d"), platform: "android" } });
  const d2 = await prisma.pushDevice.create({ data: { userId: a.id, token: tok("e"), platform: "ios" } });
  const s = sender();

  const first = await dispatchDueReminders(s, now);
  expect(first).toMatchObject({ due: 1, sent: 2, failed: 0 });
  expect(s.sent).toHaveLength(2);
  expect(s.sent.map((m) => m.token).sort()).toEqual([d1.token, d2.token].sort());
  for (const m of s.sent) {
    expect(m.title).toBe("Pengingat beOkay");
    expect(JSON.stringify(m)).not.toMatch(/Metformin|Rahasia|obat|mg\/dL/i); // judul pengguna dan nama obat tidak ikut
    expect(m.data).toEqual({ type: "reminder" });
  }

  // Putaran ulang (atau instans lain) tidak mengirim dua kali.
  const again = await dispatchDueReminders(s, new Date(now.getTime() + 5_000));
  expect(again.sent).toBe(0);
  expect(s.sent).toHaveLength(2);
  expect(await prisma.pushDelivery.count({ where: { reminderId: r.id, status: "sent" } })).toBe(2);
});

test("Pengirim: pengingat basi, nonaktif, belum waktunya, atau consent ditarik tidak dikirim; token tidak berlaku dinonaktifkan", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const now = new Date();
  const mk = async () => { const u = await actor(); await prisma.pushDevice.create({ data: { userId: u.id, token: tok("z"), platform: "android" } }); return u; };

  const stale = await mk();
  await withReminder(stale.id, new Date(now.getTime() - 10 * 60_000)); // 10 menit lalu > 3 menit
  const future = await mk();
  await withReminder(future.id, new Date(now.getTime() + 10 * 60_000));
  const off = await mk();
  await prisma.reminder.update({ where: { id: (await withReminder(off.id, new Date(now.getTime() - 60_000))).id }, data: { enabled: false } });
  const withdrawn = await mk();
  await withReminder(withdrawn.id, new Date(now.getTime() - 60_000));
  await call("/api/me/consents/withdraw", withdrawn.token, { purposes: ["health_data_processing"] });

  const s = sender();
  const out = await dispatchDueReminders(s, now);
  // Basis data uji dipakai bersama: yang diperiksa adalah tidak ada pesan terkirim ke perangkat keempat akun di atas.
  const theirDevices = new Set((await prisma.pushDevice.findMany({ where: { userId: { in: [stale.id, future.id, off.id, withdrawn.id] } } })).map((d) => d.token));
  expect(s.sent.filter((m) => theirDevices.has(m.token))).toHaveLength(0);
  expect(out.skippedNoConsent).toBeGreaterThanOrEqual(1);

  // Token tidak berlaku → perangkat dinonaktifkan dan tidak dicoba lagi.
  const u = await actor();
  const dev = await prisma.pushDevice.create({ data: { userId: u.id, token: tok("q"), platform: "android" } });
  await withReminder(u.id, new Date(now.getTime() - 30_000));
  const bad = sender(() => ({ status: "invalid_token", errorCode: "UNREGISTERED", shouldDeactivate: true }));
  const r1 = await dispatchDueReminders(bad, now);
  expect(r1.deactivated).toBe(1);
  expect((await prisma.pushDevice.findUniqueOrThrow({ where: { id: dev.id } })).active).toBe(false);
  expect((await prisma.pushDevice.findUniqueOrThrow({ where: { id: dev.id } })).lastError).toBe("UNREGISTERED");
  const r2 = await dispatchDueReminders(bad, new Date(now.getTime() + 1000));
  expect(bad.sent).toHaveLength(1);
  expect(r2.sent + r2.failed).toBe(0);

  // Kegagalan sementara dicatat sebagai failed tanpa menonaktifkan.
  const u2 = await actor();
  const dev2 = await prisma.pushDevice.create({ data: { userId: u2.id, token: tok("w"), platform: "android" } });
  await withReminder(u2.id, new Date(now.getTime() - 30_000));
  const flaky = sender(() => ({ status: "failed", errorCode: "UNAVAILABLE", shouldDeactivate: false }));
  expect((await dispatchDueReminders(flaky, now)).failed).toBeGreaterThanOrEqual(1);
  expect((await prisma.pushDevice.findUniqueOrThrow({ where: { id: dev2.id } })).active).toBe(true);
  expect(await prisma.pushDelivery.count({ where: { deviceId: dev2.id, status: "failed", errorCode: "UNAVAILABLE" } })).toBe(1);
});

test("Pengirim: tidak dikonfigurasi = tidak melakukan apa pun", async () => {
  const stats = await dispatchDueReminders({ configured: false, async send() { throw new Error("tidak boleh dipanggil"); } });
  expect(stats).toEqual({ users: 0, due: 0, sent: 0, failed: 0, deactivated: 0, skippedNoConsent: 0 });
});

test("Hapus akun menghapus perangkat dan buku besar pengiriman (cascade)", async () => {
  const a = await actor();
  const r = await withReminder(a.id, new Date(Date.now() - 30_000));
  const d = await prisma.pushDevice.create({ data: { userId: a.id, token: tok("c"), platform: "android" } });
  await dispatchDueReminders(sender(), new Date());
  expect(await prisma.pushDelivery.count({ where: { deviceId: d.id } })).toBe(1);
  await prisma.users.delete({ where: { id: a.id } });
  expect(await prisma.pushDevice.count({ where: { id: d.id } })).toBe(0);
  expect(await prisma.pushDelivery.count({ where: { reminderId: r.id } })).toBe(0);
});
