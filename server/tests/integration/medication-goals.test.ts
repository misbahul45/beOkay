import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor() {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `medgoal-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
  await call("/api/me/preferences", token, undefined, "PATCH").catch(() => {});
  await fetch(api + "/api/me/preferences", { method: "PATCH", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ timezone: "Asia/Jakarta" }) });
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;
const todayLocal = () => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" }).format(new Date());
const weekday = (d: string) => new Date(d + "T00:00:00Z").getUTCDay() || 7;

test("Medication: regimen, schedule, intake, correction, isolation, no assumed intake", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor();
  expect((await call("/api/me/medications")).status).toBe(401);
  const noConsent = crypto.randomUUID();
  users.push(noConsent);
  await prisma.users.create({ data: { id: noConsent, name: "NC", email: `nc-${noConsent}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  const t = crypto.randomUUID();
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: noConsent, token: t, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  expect((await call("/api/me/medications", t)).status).toBe(403);

  const regimen = { id: crypto.randomUUID(), name: "Obat uji sintetis", strength: "500 mg", dosageForm: "tablet", dosingInstructions: "Sesuai instruksi yang dilaporkan pengguna" };
  const created = await call("/api/me/medications", a.token, regimen);
  expect(created.status).toBe(201);
  const r = await J(created);
  expect(r.instructionSource).toBe("user_reported");
  expect((await call("/api/me/medications", a.token, regimen)).status).toBe(201); // idempotent retry
  expect((await call("/api/me/medications", a.token, { ...regimen, name: "Berbeda" })).status).toBe(409);
  expect((await call("/api/me/medications", a.token, { id: crypto.randomUUID(), name: "  " })).status).toBe(400);
  expect((await call(`/api/me/medications/${r.id}`, b.token)).status).toBe(404); // no disclosure across users

  const today = todayLocal();
  const sched = { id: crypto.randomUUID(), localTime: "08:00", timezone: "Asia/Jakarta", daysOfWeek: [weekday(today)], effectiveFrom: today };
  expect((await call(`/api/me/medications/${r.id}/schedules`, a.token, sched)).status).toBe(201);
  expect((await call(`/api/me/medications/${r.id}/schedules`, b.token, { ...sched, id: crypto.randomUUID() })).status).toBe(404);

  let summary = await J(await call("/api/me/medications/today", a.token));
  expect(summary).toMatchObject({ scheduled: 1, taken: 0, unknown: 1, coverageStatus: "UNKNOWN" });
  expect(summary.items[0].status).toBe("unknown"); // a schedule is not evidence of intake
  const scheduledAt = summary.items[0].scheduledAt;

  const intake = { id: crypto.randomUUID(), scheduleId: sched.id, scheduledAt: new Date(scheduledAt).toISOString(), status: "taken", takenAt: new Date(Date.now() - 60000).toISOString() };
  const ok = await call(`/api/me/medications/${r.id}/intakes`, a.token, intake);
  expect(ok.status).toBe(201);
  const row = await J(ok);
  expect(row.medicationSnapshot).toMatchObject({ name: "Obat uji sintetis", strength: "500 mg", scheduleLocalTime: "08:00" });
  expect((await call(`/api/me/medications/${r.id}/intakes`, a.token, intake)).status).toBe(201); // duplicate confirm is idempotent
  expect((await call(`/api/me/medications/${r.id}/intakes`, a.token, { ...intake, id: crypto.randomUUID() })).status).toBe(409); // same occurrence, new id
  summary = await J(await call("/api/me/medications/today", a.token));
  expect(summary).toMatchObject({ taken: 1, unknown: 0, coverageStatus: "COMPLETE" });

  // Changing the regimen must not rewrite the past intake snapshot.
  const patched = await J(await call(`/api/me/medications/${r.id}`, a.token, { name: "Nama baru", expectedVersion: 1, reason: "Koreksi nama" }, "PATCH"));
  expect(patched.version).toBe(2);
  expect((await call(`/api/me/medications/${r.id}`, a.token, { name: "Basi", expectedVersion: 1, reason: "x" }, "PATCH")).status).toBe(409);
  const after = await J(await call(`/api/me/medications/${r.id}/intakes/${row.id}`, a.token));
  expect(after.medicationSnapshot.name).toBe("Obat uji sintetis");

  // Correct the intake, then archive it: the occurrence returns to unknown.
  const fixed = await J(await call(`/api/me/medications/${r.id}/intakes/${row.id}`, a.token, { status: "skipped", expectedVersion: 1, reason: "Salah catat" }, "PATCH"));
  expect(fixed).toMatchObject({ status: "skipped", takenAt: null, version: 2 });
  expect((await call(`/api/me/medications/${r.id}/intakes/${row.id}`, a.token, { notes: "x", expectedVersion: 1, reason: "stale" }, "PATCH")).status).toBe(409);
  await call(`/api/me/medications/${r.id}/intakes/${row.id}`, a.token, { archived: true, expectedVersion: 2, reason: "Hapus" }, "PATCH");
  summary = await J(await call("/api/me/medications/today", a.token));
  expect(summary).toMatchObject({ taken: 0, skipped: 0, unknown: 1 });
  expect((await J(await call(`/api/me/medications/${r.id}/revisions`, a.token))).items).toHaveLength(1);
  expect((await call(`/api/me/medications/${r.id}/intakes/${row.id}`, b.token)).status).toBe(404);

  // Pausing a regimen removes it from today's occurrences without deleting history.
  await call(`/api/me/medications/${r.id}`, a.token, { status: "paused", expectedVersion: 2, reason: "Jeda" }, "PATCH");
  expect((await J(await call("/api/me/medications/today", a.token))).scheduled).toBe(0);
});

test("Goals: derived progress recalculates after corrections; check-ins; isolation", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor();
  const today = todayLocal();
  const start = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
  const goal = { id: crypto.randomUUID(), title: "Jalan 60 menit minggu ini", goalType: "activity_minutes", targetValue: 60, period: "weekly", startDate: start, endDate: null };
  expect((await call("/api/me/goals", a.token, goal)).status).toBe(201);
  expect((await call("/api/me/goals", a.token, goal)).status).toBe(201);
  expect((await call("/api/me/goals", a.token, { ...goal, targetValue: 5 })).status).toBe(409);
  expect((await call(`/api/me/goals/${goal.id}`, b.token)).status).toBe(404);
  let g = await J(await call(`/api/me/goals/${goal.id}`, a.token));
  expect(g.progress).toMatchObject({ value: null, coverageStatus: "NO_RECORDS" }); // no records is not "failed"

  const act = { id: crypto.randomUUID(), activityType: "walking", startedAt: new Date(Date.now() - 3600000).toISOString(), durationMinutes: 30 };
  expect((await call("/api/me/activities", a.token, act)).status).toBe(201);
  g = await J(await call(`/api/me/goals/${goal.id}`, a.token));
  expect(g.progress).toMatchObject({ value: 30, ratio: 0.5 });
  const fixed = await call(`/api/me/activities/${act.id}`, a.token, { durationMinutes: 45, expectedVersion: 1, reason: "Koreksi durasi" }, "PATCH");
  expect(fixed.status).toBe(200);
  expect((await J(await call(`/api/me/goals/${goal.id}`, a.token))).progress.value).toBe(45);
  await call(`/api/me/activities/${act.id}`, a.token, { archived: true, expectedVersion: 2, reason: "Hapus" }, "PATCH");
  expect((await J(await call(`/api/me/goals/${goal.id}`, a.token))).progress.value).toBeNull();

  expect((await call(`/api/me/goals/${goal.id}/checkins`, a.token, { id: crypto.randomUUID(), eventAt: new Date().toISOString(), status: "completed" })).status).toBe(422);

  const manual = { id: crypto.randomUUID(), title: "Latihan peregangan", goalType: "manual_checkins", targetValue: 3, period: "weekly", startDate: start, endDate: null };
  await call("/api/me/goals", a.token, manual);
  const ck = { id: crypto.randomUUID(), eventAt: new Date().toISOString(), status: "completed" };
  const made = await call(`/api/me/goals/${manual.id}/checkins`, a.token, ck);
  expect(made.status).toBe(201);
  expect((await call(`/api/me/goals/${manual.id}/checkins`, a.token, ck)).status).toBe(201);
  expect((await call(`/api/me/goals/${manual.id}/checkins`, b.token, { ...ck, id: crypto.randomUUID() })).status).toBe(404);
  expect((await J(await call(`/api/me/goals/${manual.id}`, a.token))).progress).toMatchObject({ value: 1, completedCount: 1 });
  await call(`/api/me/goals/${manual.id}/checkins/${ck.id}`, a.token, { status: "skipped", expectedVersion: 1, reason: "Salah" }, "PATCH");
  expect((await J(await call(`/api/me/goals/${manual.id}`, a.token))).progress).toMatchObject({ completedCount: 0, skippedCount: 1 });
  expect((await call(`/api/me/goals/${manual.id}/checkins/${ck.id}`, a.token, { status: "completed", expectedVersion: 1, reason: "stale" }, "PATCH")).status).toBe(409);

  const paused = await J(await call(`/api/me/goals/${manual.id}`, a.token, { status: "paused", expectedVersion: 1, reason: "Jeda" }, "PATCH"));
  expect(paused.status).toBe("paused");
  expect((await J(await call("/api/me/goals", a.token))).items.length).toBe(2);
});

test("Timeline includes medication intakes and goal check-ins with navigable parents, archived excluded", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor();
  const today = todayLocal();
  const reg = { id: crypto.randomUUID(), name: "Obat timeline" };
  await call("/api/me/medications", a.token, reg);
  const intake = { id: crypto.randomUUID(), status: "skipped" };
  await call(`/api/me/medications/${reg.id}/intakes`, a.token, intake);
  const goal = { id: crypto.randomUUID(), title: "Check-in timeline", goalType: "manual_checkins", targetValue: 2, period: "daily", startDate: today, endDate: null };
  await call("/api/me/goals", a.token, goal);
  const ck = { id: crypto.randomUUID(), eventAt: new Date().toISOString(), status: "completed" };
  await call(`/api/me/goals/${goal.id}/checkins`, a.token, ck);
  const tl = await J(await call("/api/me/timeline?domain=all&limit=10", a.token));
  expect(tl.supportedDomains).toContain("medication");
  const med = tl.items.find((i: any) => i.domain === "medication");
  expect(med).toMatchObject({ recordId: intake.id, regimenId: reg.id, medicationName: "Obat timeline", status: "skipped" });
  expect(tl.items.find((i: any) => i.domain === "goal")).toMatchObject({ recordId: ck.id, goalId: goal.id, goalTitle: "Check-in timeline" });
  expect((await J(await call("/api/me/timeline?domain=medication", a.token))).items.every((i: any) => i.domain === "medication")).toBe(true);
  await call(`/api/me/medications/${reg.id}/intakes/${intake.id}`, a.token, { archived: true, expectedVersion: 1, reason: "Hapus" }, "PATCH");
  expect((await J(await call("/api/me/timeline?domain=medication", a.token))).items).toHaveLength(0);
});
