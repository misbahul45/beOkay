import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { interventionService } from "../../src/features/interventions/intervention.service.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
async function actor(purposes = ["health_data_processing", "personalized_ai"], tz = "Asia/Jakarta") {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "F", email: `iv-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = await J(await call("/api/consent-policies/current", token));
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  await call("/api/me/preferences", token, { timezone: tz }, "PATCH");
  return { id, token };
}
const goal = (userId: string, title = "Jalan sore") => prisma.behaviorGoal.create({ data: { userId, title, goalType: "manual_checkins", targetValue: 3, period: "weekly", startDate: new Date("2026-11-01"), createHash: crypto.randomUUID() } });
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
// 10:00 WIB = 03:00Z; 23:00 WIB = 16:00Z
const at = (h: number, day = 10) => new Date(Date.UTC(2026, 10, day, h, 0, 0));
const WIB10 = at(3), WIB23 = at(16), WIB14 = at(7);
const ev = (userId: string, trigger: any, now: Date, goalId?: string) => interventionService.evaluate(userId, { trigger, ...(goalId ? { goalId } : {}) }, now);

test("Akses: butuh login; pemicu dan isi dibatasi skema; pengguna lain tidak dapat memakai tujuan atau saran orang lain", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  expect((await call("/api/me/interventions")).status).toBe(401);
  const a = await actor(), b = await actor();
  expect((await call("/api/me/interventions/evaluate", a.token, { trigger: "SPAM" })).status).toBe(400);
  expect((await call("/api/me/interventions/evaluate", a.token, { trigger: "WEEKLY_REVIEW_AVAILABLE", extra: 1 })).status).toBe(400);
  const g = await goal(a.id);
  expect((await call("/api/me/interventions/evaluate", b.token, { trigger: "GOAL_WINDOW_APPROACHING", goalId: g.id })).status).toBe(404); // tujuan orang lain
  const ok = await J(await call("/api/me/interventions/evaluate", a.token, { trigger: "USER_REQUESTS_SUPPORT" }));
  expect(ok).toMatchObject({ option: "IN_APP_SUGGESTION", trigger: "USER_REQUESTS_SUPPORT" });
  expect((await call(`/api/me/interventions/${ok.id}/response`, b.token, { kind: "USEFUL" })).status).toBe(404);
  expect((await J(await call("/api/me/interventions", b.token))).items).toEqual([]);
});

test("Tanpa persetujuan: tidak ada intervensi dan alasannya tercatat; pencabutan membatalkan kartu yang terbuka dan menutup penanggapan", async () => {
  const none = await actor(["health_data_processing"]);
  const r = await ev(none.id, "USER_REQUESTS_SUPPORT", WIB10);
  expect(r).toMatchObject({ option: "NO_INTERVENTION", reason: "CONSENT_MISSING", deliveryStatus: "NOT_APPLICABLE" });
  const a = await actor();
  const shown = await ev(a.id, "USER_REQUESTS_SUPPORT", WIB10);
  expect((await interventionService.listOpen(a.id, WIB10)).items.length).toBe(1);
  await call("/api/me/consents/withdraw", a.token, { purposes: ["personalized_ai"] });
  expect(await interventionService.listOpen(a.id, WIB10)).toEqual({ items: [], consentRequired: true });
  expect((await prisma.interventionDecision.findUniqueOrThrow({ where: { id: shown.id } })).deliveryStatus).toBe("CANCELLED");
  expect((await call(`/api/me/interventions/${shown.id}/response`, a.token, { kind: "USEFUL" })).status).toBe(403);
});

test("Jam tenang: pemicu proaktif ditahan; di luar jam tenang diizinkan; permintaan sendiri tetap dilayani", async () => {
  const a = await actor();
  const g = await goal(a.id);
  expect(await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB23, g.id)).toMatchObject({ option: "NO_INTERVENTION", reason: "QUIET_HOURS" });
  expect(await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB10, g.id)).toMatchObject({ option: "GOAL_REVIEW_CARD", content: { action: "OPEN_GOALS" } });
  expect(await ev(a.id, "USER_REQUESTS_SUPPORT", WIB23)).toMatchObject({ option: "IN_APP_SUGGESTION" });
  // Jam tenang diatur pengguna: 09:00–11:00 → jam 10 ditahan.
  const b = await actor();
  await interventionService.updatePreferences(b.id, { quietStartMinute: 9 * 60, quietEndMinute: 11 * 60 });
  expect(await ev(b.id, "WEEKLY_REVIEW_AVAILABLE", WIB10)).toMatchObject({ reason: "QUIET_HOURS" });
});

test("Pemicu ganda: tidak ada saran ganda; keputusan yang sama dikembalikan dan tidak ada baris baru; pemicu bersamaan hanya satu", async () => {
  const a = await actor();
  const first = await ev(a.id, "WEEKLY_REVIEW_AVAILABLE", WIB10);
  const again = await ev(a.id, "WEEKLY_REVIEW_AVAILABLE", new Date(WIB10.getTime() + 60_000));
  expect(again).toMatchObject({ id: first.id, replayed: true });
  const racing = await Promise.all([1, 2, 3, 4].map(() => ev(a.id, "USER_REQUESTS_SUPPORT", WIB10)));
  expect(new Set(racing.map((r) => r.id)).size).toBe(1);
  expect(await prisma.interventionDecision.count({ where: { userId: a.id, option: { not: "NO_INTERVENTION" } } })).toBe(2);
});

test("Jatah dan jeda minimum: batas harian, jarak antar-saran, dan batas mingguan dapat diatur pengguna", async () => {
  const a = await actor();
  const g = await goal(a.id);
  await interventionService.updatePreferences(a.id, { maxPerDay: 1 });
  expect((await ev(a.id, "WEEKLY_REVIEW_AVAILABLE", WIB10)).option).toBe("WEEKLY_REFLECTION");
  expect(await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB14, g.id)).toMatchObject({ reason: "DAILY_LIMIT" });
  await interventionService.updatePreferences(a.id, { maxPerDay: 3 });
  expect(await ev(a.id, "GOAL_WINDOW_APPROACHING", new Date(WIB10.getTime() + 3_600_000), g.id)).toMatchObject({ reason: "TOO_SOON" });
  expect((await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB14, g.id)).option).toBe("GOAL_REVIEW_CARD");
  await interventionService.updatePreferences(a.id, { maxPerDay: 0 });
  expect(await ev(a.id, "USER_SELECTED_ROUTINE_REMINDER", at(9), g.id)).toMatchObject({ reason: "DAILY_LIMIT" }); // pengguna boleh menolak semua proaktif
});

test("Jeda: pemicu proaktif berhenti dan kartu proaktif terbuka dibatalkan; permintaan sendiri tetap; dilanjutkan → kembali", async () => {
  const a = await actor();
  const g = await goal(a.id);
  const card = await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB10, g.id);
  const prefs = await interventionService.updatePreferences(a.id, { pauseForHours: 48 }, WIB10);
  expect(prefs.pausedUntil).toBe(new Date(WIB10.getTime() + 48 * 3_600_000).toISOString());
  expect((await prisma.interventionDecision.findUniqueOrThrow({ where: { id: card.id } })).deliveryStatus).toBe("CANCELLED");
  expect(await ev(a.id, "WEEKLY_REVIEW_AVAILABLE", WIB14)).toMatchObject({ reason: "COACHING_PAUSED" });
  expect((await ev(a.id, "USER_REQUESTS_SUPPORT", WIB14)).option).toBe("IN_APP_SUGGESTION");
  await interventionService.updatePreferences(a.id, { resume: true });
  expect((await ev(a.id, "WEEKLY_REVIEW_AVAILABLE", at(8))).option).toBe("WEEKLY_REFLECTION");
});

test("Setiap jawaban punya akibat nyata: ditunda muncul lagi setelahnya, sudah dilakukan menahan ulangan hari itu, berhenti mematikan jenis itu, terlalu sering memperketat jatah", async () => {
  const a = await actor();
  const g = await goal(a.id);
  // NOT_NOW
  const c1 = await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB10, g.id);
  const snoozed = await interventionService.respond(a.id, c1.id, { kind: "NOT_NOW", snoozeMinutes: 120 }, WIB10);
  expect(snoozed).toMatchObject({ deliveryStatus: "SNOOZED", response: "NOT_NOW" });
  expect((await interventionService.listOpen(a.id, new Date(WIB10.getTime() + 60 * 60_000))).items).toEqual([]); // belum waktunya
  expect(await ev(a.id, "GOAL_WINDOW_APPROACHING", new Date(WIB10.getTime() + 60 * 60_000), g.id)).toMatchObject({ reason: "SNOOZED" });
  const later = await interventionService.listOpen(a.id, new Date(WIB10.getTime() + 121 * 60_000));
  expect(later.items.map((x: any) => x.id)).toEqual([c1.id]); // muncul lagi, tanpa saran baru

  // ALREADY_DONE
  const b = await actor();
  const gb = await goal(b.id);
  const cb = await ev(b.id, "GOAL_WINDOW_APPROACHING", WIB10, gb.id);
  await interventionService.respond(b.id, cb.id, { kind: "ALREADY_DONE" }, WIB10);
  expect(await ev(b.id, "GOAL_WINDOW_APPROACHING", at(15), gb.id)).toMatchObject({ reason: "ALREADY_DONE_TODAY" });

  // STOP_THIS_TYPE
  const c = await actor();
  const gc = await goal(c.id);
  const cc = await ev(c.id, "GOAL_WINDOW_APPROACHING", WIB10, gc.id);
  await interventionService.respond(c.id, cc.id, { kind: "STOP_THIS_TYPE" }, WIB10);
  expect((await interventionService.getPreferences(c.id)).mutedTriggers).toEqual(["GOAL_WINDOW_APPROACHING"]);
  expect(await ev(c.id, "GOAL_WINDOW_APPROACHING", at(20, 12), gc.id)).toMatchObject({ reason: "TRIGGER_MUTED" });
  expect((await ev(c.id, "WEEKLY_REVIEW_AVAILABLE", at(8, 13))).option).toBe("WEEKLY_REFLECTION"); // jenis lain tidak terpengaruh

  // TOO_FREQUENT
  const d = await actor();
  const cd = await ev(d.id, "WEEKLY_REVIEW_AVAILABLE", WIB10);
  await interventionService.respond(d.id, cd.id, { kind: "TOO_FREQUENT" }, WIB10);
  expect(await interventionService.getPreferences(d.id)).toMatchObject({ maxPerDay: 1, maxPerWeek: 3 });

  // USEFUL / NOT_USEFUL / DISMISSED hanya dicatat; peristiwa outbox ditulis sekali per jawaban.
  for (const kind of ["USEFUL", "NOT_USEFUL", "DISMISSED"] as const) {
    const u = await actor();
    const x = await ev(u.id, "USER_REQUESTS_SUPPORT", WIB10);
    expect(await interventionService.respond(u.id, x.id, { kind }, WIB10)).toMatchObject({ response: kind, deliveryStatus: "RESPONDED" });
    expect(await prisma.outboxEvent.count({ where: { userId: u.id, type: "intervention.responded" } })).toBe(1);
  }
});

test("Jawaban: pertama menang, ulangan sama aman, jawaban berbeda 409; jawaban pada 'tidak mengintervensi' ditolak; skema membatasi masukan", async () => {
  const a = await actor();
  const x = await ev(a.id, "USER_REQUESTS_SUPPORT", WIB10);
  expect((await call(`/api/me/interventions/${x.id}/response`, a.token, { kind: "USEFUL" })).status).toBe(200);
  expect(await J(await call(`/api/me/interventions/${x.id}/response`, a.token, { kind: "USEFUL" }))).toMatchObject({ replayed: true });
  expect((await call(`/api/me/interventions/${x.id}/response`, a.token, { kind: "NOT_USEFUL" })).status).toBe(409);
  const blocked = await ev((await actor(["health_data_processing"])).id, "USER_REQUESTS_SUPPORT", WIB10);
  expect((await call(`/api/me/interventions/${blocked.id}/response`, a.token, { kind: "USEFUL" })).status).toBe(404);
  const y = await ev(a.id, "WEEKLY_REVIEW_AVAILABLE", at(8));
  expect((await call(`/api/me/interventions/${y.id}/response`, a.token, { kind: "NOT_NOW", snoozeMinutes: 1 })).status).toBe(400);
  expect((await call(`/api/me/interventions/${y.id}/response`, a.token, { kind: "MAYBE" })).status).toBe(400);
  expect((await call("/api/me/intervention-preferences", a.token, { pauseForHours: 5, resume: true }, "PATCH")).status).toBe(400);
  expect((await call("/api/me/intervention-preferences", a.token, { maxPerDay: 99 }, "PATCH")).status).toBe(400);
});

test("Tanpa eskalasi karena diam: saran proaktif yang tidak ditanggapi tidak diulang hari berikutnya dan kedaluwarsa; tidak ada saran kedaluwarsa yang ditampilkan", async () => {
  const a = await actor();
  const g = await goal(a.id);
  const day1 = await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB10, g.id);
  expect(await ev(a.id, "GOAL_WINDOW_APPROACHING", at(3, 11), g.id)).toMatchObject({ option: "NO_INTERVENTION", reason: "REPEAT_SUPPRESSED" });
  expect((await interventionService.listOpen(a.id, new Date(WIB10.getTime() + 13 * 3_600_000))).items).toEqual([]); // kedaluwarsa 12 jam
  expect((await prisma.interventionDecision.findUniqueOrThrow({ where: { id: day1.id } })).deliveryStatus).toBe("EXPIRED");
  expect(await interventionService.respond(a.id, day1.id, { kind: "USEFUL" }, WIB14).catch((e) => e.code ?? e.status)).toBeTruthy();
  const after = await ev(a.id, "GOAL_WINDOW_APPROACHING", at(3, 14), g.id); // lewat jendela penekanan 2 hari
  expect(after.option).toBe("GOAL_REVIEW_CARD");
});

test("Zona waktu berubah: pemicu yang sama dalam 12 jam tidak menghasilkan saran kedua; tanggal lokal mengikuti zona waktu terbaru", async () => {
  const a = await actor();
  const first = await ev(a.id, "WEEKLY_REVIEW_AVAILABLE", WIB10);
  await call("/api/me/preferences", a.token, { timezone: "Asia/Makassar" }, "PATCH");
  const after = await ev(a.id, "WEEKLY_REVIEW_AVAILABLE", new Date(WIB10.getTime() + 3_600_000));
  expect(after).toMatchObject({ id: first.id, replayed: true });
  const tokyo = await actor(undefined, "Pacific/Kiritimati"); // UTC+14: 03:00Z = 17:00 lokal tanggal yang sama; 10:00Z = 00:00 tanggal berikutnya (jam tenang)
  expect(await ev(tokyo.id, "WEEKLY_REVIEW_AVAILABLE", at(10))).toMatchObject({ reason: "QUIET_HOURS" });
  expect((await prisma.interventionDecision.findFirstOrThrow({ where: { userId: tokyo.id } })).localDate).toBe("2026-11-11");
});

test("Isi dan log: tidak ada nilai klinis; keputusan 'tidak' punya alasan; log hanya milik pengguna; versi kebijakan tercatat", async () => {
  const a = await actor();
  const g = await goal(a.id, "Jalan sore");
  const card = await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB10, g.id);
  expect(Object.keys(card.content as object).sort()).toEqual(["action", "body", "title"]);
  expect(JSON.stringify(card)).not.toMatch(/glukosa|obat|dosis|diabetes|mg\/dL/i);
  await ev(a.id, "GOAL_WINDOW_APPROACHING", WIB23, g.id);
  const rows = await prisma.interventionDecision.findMany({ where: { userId: a.id } });
  expect(rows.every((r) => r.policyVersion === "jitai-policy-v2")).toBe(true);
  for (const r of rows.filter((x) => x.option === "NO_INTERVENTION")) expect(r.reason).toBeTruthy();
  // DB menolak 'tidak mengintervensi' tanpa alasan.
  const bad = await prisma.interventionDecision.create({ data: { userId: a.id, triggerType: "USER_REQUESTS_SUPPORT", localDate: "2026-11-10", timezone: "Asia/Jakarta", policyVersion: "x", eligibilityStatus: "BLOCKED", dataCoverage: "NONE", option: "NO_INTERVENTION", approvalStatus: "NOT_REQUIRED", deliveryStatus: "NOT_APPLICABLE" } }).then(() => false, () => true);
  expect(bad).toBe(true);
});

test("Dibuka bukan tanggapan: kartu hilang dari daftar, tidak dihitung berguna, masih bisa dinilai, dan ulangan aman", async () => {
  const a = await actor();
  const x = await ev(a.id, "USER_REQUESTS_SUPPORT", WIB10);
  const opened = await interventionService.respond(a.id, x.id, { kind: "OPENED" }, WIB10);
  expect(opened).toMatchObject({ deliveryStatus: "OPENED", response: null });
  expect(await interventionService.respond(a.id, x.id, { kind: "OPENED" }, WIB10)).toMatchObject({ replayed: true });
  expect((await interventionService.listOpen(a.id, WIB10)).items).toEqual([]);
  expect(await prisma.outboxEvent.count({ where: { userId: a.id, type: "intervention.responded" } })).toBe(0); // bukan tanggapan
  expect(await interventionService.respond(a.id, x.id, { kind: "USEFUL" }, WIB10)).toMatchObject({ deliveryStatus: "RESPONDED", response: "USEFUL" });
});
