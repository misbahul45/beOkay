import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { addDays } from "../../src/features/coaching/coaching.model.ts";
import { coachingService } from "../../src/features/coaching/coaching.service.ts";
import { interventionService } from "../../src/features/interventions/intervention.service.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
const ALL = ["health_data_processing", "descriptive_summaries", "personalized_ai"];
const op = () => crypto.randomUUID();
const hash = () => (crypto.randomUUID() + crypto.randomUUID()).replace(/-/g, "");

async function actor(purposes = ALL) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "C", email: `co-${id}@example.test`, emailVerified: true, createdAt: new Date(Date.now() - 40 * 86_400_000), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = await J(await call("/api/consent-policies/current", token));
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });

const realToday = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta" }).format(new Date());
const D0 = addDays(realToday, -4);
const wib = (date: string, hh = 12, mm = 0) => new Date(`${date}T${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}:00+07:00`);
const meal = (userId: string, date: string, category: string, hh = 12) => prisma.mealLog.create({ data: { userId, category, consumedAt: wib(date, hh), createHash: hash() } });
const session = (userId: string, date: string, minutes: number, type = "walking", hh = 7) =>
  prisma.activitySession.create({ data: { userId, activityType: type, startedAt: wib(date, hh), endedAt: new Date(wib(date, hh).getTime() + minutes * 60_000), durationMinutes: minutes, createHash: hash() } });
async function lunchGap(userId: string) {
  for (let i = 1; i <= 9; i++) {
    const d = addDays(D0, -i);
    await meal(userId, d, "breakfast", 7);
    await meal(userId, d, "dinner", 19);
    if (i <= 2) await meal(userId, d, "lunch", 12);
  }
}
const prefs = async (userId: string) => ((await prisma.personalizationProfile.findUnique({ where: { userId } }))?.data as any)?.coaching ?? {};

test("Akses dan skema: butuh login, isi dibatasi skema, rencana orang lain tidak terlihat, tanpa persetujuan tidak ada usulan", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  expect((await call("/api/me/coaching")).status).toBe(401);
  const a = await actor(), b = await actor();
  await lunchGap(a.id);
  const list = await J(await call("/api/me/coaching/opportunities", a.token));
  const id = list.items[0].id;
  expect((await call(`/api/me/coaching/actions/${id}/decision`, a.token, { operationId: op(), decision: "ACCEPT", extra: 1 })).status).toBe(400);
  expect((await call(`/api/me/coaching/actions/${id}/decision`, a.token, { operationId: op(), decision: "DECLINE", slot: "MORNING" })).status).toBe(400);
  expect((await call(`/api/me/coaching/actions/${id}/feedback`, a.token, { operationId: op(), kind: "PREFER_DIFFERENT_TIME" })).status).toBe(400);
  expect((await call(`/api/me/coaching/actions/${id}/decision`, b.token, { operationId: op(), decision: "ACCEPT" })).status).toBe(404);
  expect((await J(await call("/api/me/coaching", b.token))).opportunities.map((o: any) => o.id)).not.toContain(id);
  const none = await actor(["health_data_processing"]);
  await lunchGap(none.id);
  expect(await J(await call("/api/me/coaching/opportunities", none.token))).toMatchObject({ consentRequired: true, items: [] });
  expect(await J(await call("/api/me/coaching/checkins", await actor(["health_data_processing"]).then((x) => x.token)))).toEqual({ consentRequired: true });
});

test("Lingkar tertutup makan: usulan dari catatan → diterima tepat sekali dengan pengingat → tercatat → bukti ditarik → dikonfirmasi sendiri → belum terlihat → pengingat diarsipkan", async () => {
  const a = await actor();
  await lunchGap(a.id);
  const NOW = wib(D0, 10);
  const opp = await coachingService.opportunities(a.id, NOW);
  expect(opp.items).toHaveLength(1);
  const p = opp.items[0]!;
  expect(p).toMatchObject({ source: "MEAL_LOG_GAP", status: "PROPOSED", title: "Catat makan siang 3 hari ke depan", dayStates: [] });
  expect((p.evidence as any).summary).toBe("Makan siang tercatat di 2 dari 9 hari yang punya catatan makan.");
  expect((await coachingService.opportunities(a.id, NOW)).items[0]!.id).toBe(p.id);

  const accept = op();
  const acc = await coachingService.decide(a.id, p.id, { operationId: accept, decision: "ACCEPT", slot: "MIDDAY", reminder: {} }, NOW);
  expect(acc).toMatchObject({ status: "ACCEPTED", phase: "RUNNING", startDate: D0, endDate: addDays(D0, 2), slot: "MIDDAY", reminder: { localTime: "12:00", enabled: true }, replayed: false });
  expect(acc.dayStates.map((d) => d.state)).toEqual(["PLANNED", "PLANNED", "PLANNED"]);
  const reminder = await prisma.reminder.findFirstOrThrow({ where: { userId: a.id } });
  expect(reminder).toMatchObject({ kind: "meal", title: "Catat makan siang 3 hari ke depan" });
  expect(reminder.daysOfWeek.length).toBe(3);
  expect(await coachingService.decide(a.id, p.id, { operationId: accept, decision: "ACCEPT", slot: "MIDDAY", reminder: {} }, NOW)).toMatchObject({ replayed: true, status: "ACCEPTED" });
  await expect(coachingService.decide(a.id, p.id, { operationId: accept, decision: "DECLINE" }, NOW)).rejects.toMatchObject({ code: "OPERATION_ID_REUSED" });
  await expect(coachingService.decide(a.id, p.id, { operationId: op(), decision: "ACCEPT" }, NOW)).rejects.toMatchObject({ code: "ACTION_NOT_OPEN" });
  expect(await prisma.reminder.count({ where: { userId: a.id } })).toBe(1);
  expect(await prisma.coachingEvent.count({ where: { userId: a.id, type: "DECISION" } })).toBe(1);

  const lunch = await meal(a.id, D0, "lunch", 12);
  await coachingService.reconcile(a.id, wib(D0, 13));
  let v = (await coachingService.overview(a.id, wib(D0, 13))).actions[0]!;
  expect(v.dayStates[0]).toMatchObject({ state: "OBSERVED", today: true });
  const outcome = await prisma.coachingOutcome.findFirstOrThrow({ where: { actionId: p.id } });
  expect(outcome).toMatchObject({ evidenceType: "meal_log", evidenceId: lunch.id });

  await prisma.mealLog.update({ where: { id: lunch.id }, data: { archivedAt: new Date() } });
  await coachingService.reconcile(a.id, wib(D0, 14));
  v = (await coachingService.overview(a.id, wib(D0, 14))).actions[0]!;
  expect(v.dayStates[0]!.state).toBe("RETRACTED");

  const c = op();
  expect((await coachingService.confirm(a.id, p.id, { operationId: c, date: D0 }, wib(D0, 15))).dayStates[0]!.state).toBe("USER_CONFIRMED");
  expect((await coachingService.confirm(a.id, p.id, { operationId: c, date: D0 }, wib(D0, 15))).replayed).toBe(true);
  await expect(coachingService.confirm(a.id, p.id, { operationId: op(), date: addDays(D0, 1) }, wib(D0, 15))).rejects.toMatchObject({ code: "DATE_NOT_IN_PLAN" });

  v = (await coachingService.overview(a.id, wib(addDays(D0, 2), 9))).actions[0]!;
  expect(v.dayStates.map((d) => d.state)).toEqual(["USER_CONFIRMED", "NOT_OBSERVED", "PLANNED"]);
  expect(v.summary).toMatchObject({ confirmed: 1, notObserved: 1, planned: 1 });

  const ended = await coachingService.reconcile(a.id, wib(addDays(D0, 3), 9));
  expect(ended.remindersArchived).toBe(1);
  expect((await prisma.reminder.findUniqueOrThrow({ where: { id: reminder.id } })).archivedAt).not.toBeNull();
  expect((await coachingService.overview(a.id, wib(addDays(D0, 3), 9))).actions[0]).toMatchObject({ phase: "ENDED", reminder: null });
});

test("Umpan balik: setiap jenis punya akibat yang terdokumentasi dan dapat diaudit", async () => {
  const a = await actor();
  await lunchGap(a.id);
  for (let i = 0; i <= 3; i++) await meal(a.id, addDays(D0, i), "breakfast", 7);
  const NOW = wib(D0, 10);
  const first = (await coachingService.opportunities(a.id, NOW)).items[0]!;
  expect((await coachingService.feedback(a.id, first.id, { operationId: op(), kind: "NOT_NOW" }, NOW))).toMatchObject({ status: "DECLINED", closeReason: "NOT_NOW" });
  expect((await prefs(a.id)).snoozed).toEqual({ MEAL_LOG_GAP: addDays(D0, 3) });
  const held = await coachingService.opportunities(a.id, wib(addDays(D0, 1), 10));
  expect(held.items).toEqual([]);
  expect(held.withheld).toContainEqual({ source: "MEAL_LOG_GAP", reason: "SNOOZED" });
  const ev = await prisma.personalizationEvent.findFirstOrThrow({ where: { userId: a.id, reason: "COACHING_NOT_NOW" } });
  expect(ev.change).toMatchObject({ rules: "coach-rules-v1", actionId: first.id, snoozed: { source: "MEAL_LOG_GAP", until: addDays(D0, 3) } });

  const later = wib(addDays(D0, 3), 10);
  const again = (await coachingService.opportunities(a.id, later)).items[0]!;
  expect(again.id).not.toBe(first.id);
  await coachingService.feedback(a.id, again.id, { operationId: op(), kind: "HELPFUL" }, later);
  await expect(coachingService.feedback(a.id, again.id, { operationId: op(), kind: "NOT_HELPFUL" }, later)).rejects.toMatchObject({ code: "FEEDBACK_ALREADY_RECORDED" });
  expect((await prefs(a.id)).usefulness).toEqual({ MEAL_LOG_GAP: { helpful: 1, notHelpful: 0 } });
  await coachingService.feedback(a.id, again.id, { operationId: op(), kind: "PREFER_DIFFERENT_TIME", slot: "EVENING" }, later);
  expect((await prisma.coachingAction.findUniqueOrThrow({ where: { id: again.id } })).slot).toBe("EVENING");
  expect((await prefs(a.id)).slot).toBe("EVENING");
  expect(await coachingService.feedback(a.id, again.id, { operationId: op(), kind: "PREFER_DIFFERENT_SUGGESTION" }, later)).toMatchObject({ status: "DECLINED", closeReason: "DIFFERENT_SUGGESTION" });
  const smaller = (await coachingService.opportunities(a.id, later)).items[0]!;
  expect(smaller).toMatchObject({ title: "Catat makan siang hari ini", days: 1 });

  await coachingService.feedback(a.id, smaller.id, { operationId: op(), kind: "TOO_FREQUENT" }, later);
  expect(await prisma.interventionPreference.findUniqueOrThrow({ where: { userId: a.id } })).toMatchObject({ maxPerDay: 1, maxPerWeek: 3 });
  expect((await prefs(a.id)).maxSuggestions).toBe(1);

  const last = wib(addDays(D0, 4), 10);
  await prisma.personalizationProfile.update({ where: { userId: a.id }, data: { data: { dislikedTokens: {}, likedTokens: {}, coaching: { ...(await prefs(a.id)), snoozed: {} } } } });
  const third = (await coachingService.opportunities(a.id, last)).items[0]!;
  await coachingService.feedback(a.id, third.id, { operationId: op(), kind: "STOP_THIS_TYPE" }, last);
  expect((await prefs(a.id)).muted).toEqual(["MEAL_LOG_GAP"]);
  expect((await coachingService.opportunities(a.id, last)).withheld).toContainEqual({ source: "MEAL_LOG_GAP", reason: "MUTED_BY_USER" });
  const reasons = (await prisma.personalizationEvent.findMany({ where: { userId: a.id }, orderBy: { version: "asc" } })).map((e) => e.reason);
  expect(reasons).toEqual(["COACHING_NOT_NOW", "COACHING_HELPFUL", "COACHING_PREFER_DIFFERENT_TIME", "COACHING_PREFER_DIFFERENT_SUGGESTION", "COACHING_TOO_FREQUENT", "COACHING_STOP_THIS_TYPE"]);
  expect(await prisma.coachingEvent.count({ where: { userId: a.id, type: "FEEDBACK" } })).toBe(6);
});

test("JITAI v2: rencana hari ini ditunda sampai waktunya, kartu tepat sekali, pertanyaan klarifikasi setelah 'kurang membantu', ditahan bila tidak lagi aman", async () => {
  const a = await actor();
  const start = addDays(D0, -6);
  await session(a.id, start, 20);
  await prisma.coachingAction.create({ data: { userId: a.id, opportunityKey: "GOAL_PACE:3d:x", source: "GOAL_PACE", kind: "ACTIVITY_SESSION", title: "Jalan kaki 20 menit, 3 hari", rationale: "r", evidence: { summary: "s" }, params: { activityType: "walking", durationMinutes: 20 }, startDate: new Date(start + "T00:00:00Z"), days: 3, status: "ACCEPTED", decidedAt: wib(start, 8), policyVersion: "coach-rules-v1", expiresAt: wib(start, 8) } });
  const NOW = wib(D0, 12);
  const opp = await coachingService.opportunities(a.id, NOW);
  const step = opp.items.find((o) => o.source === "ACTIVITY_STEP_DOWN")!;
  expect(step).toMatchObject({ title: "Jalan kaki 10 menit, 3 hari", params: { activityType: "walking", durationMinutes: 10 } });
  expect((step.evidence as any).summary).toBe("2 dari 3 rencana aktivitas terakhir belum terlihat di catatan.");
  await coachingService.decide(a.id, step.id, { operationId: op(), decision: "ACCEPT", slot: "AFTERNOON" }, NOW);

  const early = await interventionService.evaluate(a.id, { trigger: "COACHING_ACTION_DUE" }, NOW);
  expect(early).toMatchObject({ option: "NO_INTERVENTION", reason: "SLOT_NOT_STARTED", decision: "DEFER" });
  const card = await interventionService.evaluate(a.id, { trigger: "COACHING_ACTION_DUE" }, wib(D0, 16));
  expect(card).toMatchObject({ option: "ACTION_REMINDER_CARD", decision: "INTERVENE", content: { title: "Rencana hari ini", body: "Jalan kaki 10 menit, 3 hari · sore. Cukup langkah kecil.", action: "OPEN_COACHING" } });
  expect(await interventionService.evaluate(a.id, { trigger: "COACHING_ACTION_DUE" }, wib(D0, 17))).toMatchObject({ id: card.id, replayed: true });
  await interventionService.respond(a.id, card.id, { kind: "NOT_USEFUL" }, wib(D0, 17));

  const ask = await interventionService.evaluate(a.id, { trigger: "COACHING_ACTION_DUE" }, wib(addDays(D0, 1), 16));
  expect(ask).toMatchObject({ option: "CLARIFICATION_QUESTION", decision: "ASK_FOR_CLARIFICATION", content: { action: "ASK" } });
  await interventionService.respond(a.id, ask.id, { kind: "USEFUL" }, wib(addDays(D0, 1), 16, 5));

  await session(a.id, addDays(D0, 1), 12, "walking", 17);
  await prisma.memoryItem.create({ data: { userId: a.id, category: "PREFERENCE", kind: "ACTIVITY_DISLIKE", key: "ACTIVITY_DISLIKE:walking:jalan kaki", content: "Kurang suka jalan kaki", status: "ACTIVE", sourceType: "USER", confirmedAt: new Date() } });
  const review = await interventionService.evaluate(a.id, { trigger: "COACHING_ACTION_DUE" }, wib(addDays(D0, 2), 16));
  expect(review).toMatchObject({ option: "NO_INTERVENTION", reason: "REQUIRES_REVIEW", decision: "REQUIRES_REVIEW" });
  const view = (await coachingService.overview(a.id, wib(addDays(D0, 2), 16))).actions.find((x) => x.id === step.id)!;
  expect(view.dayStates.map((d) => d.state)).toEqual(["NOT_OBSERVED", "OBSERVED", "PLANNED"]);
  expect(await prisma.interventionDecision.count({ where: { userId: a.id, option: { not: "NO_INTERVENTION" } } })).toBe(2);
});

test("Refleksi mingguan: ringkasan dari catatan, penyesuaian tujuan hanya dengan konfirmasi, ingatan dan preferensi waktu, tepat sekali, JITAI tidak mengulang", async () => {
  const a = await actor();
  const week = await coachingService.reflectionWeek(a.id);
  for (let i = 0; i < 5; i++) await meal(a.id, addDays(week, i), "lunch");
  for (let i = 0; i < 3; i++) await session(a.id, addDays(week, i), 15);
  const goal = await prisma.behaviorGoal.create({ data: { userId: a.id, title: "Aktif 150 menit", goalType: "activity_minutes", targetValue: 150, period: "weekly", startDate: new Date(addDays(week, -14) + "T00:00:00Z"), createHash: hash() } });
  const glucoseGoal = await prisma.behaviorGoal.create({ data: { userId: a.id, title: "Cek gula 7x", goalType: "record_glucose", targetValue: 7, period: "weekly", startDate: new Date(addDays(week, -14) + "T00:00:00Z"), createHash: hash() } });

  const r = await J(await call("/api/me/coaching/checkins", a.token));
  expect(r).toMatchObject({ consentRequired: false, weekStart: week, done: null, nudge: true });
  expect(r.positives).toContain("Makan tercatat di 5 dari 7 hari");
  expect(r.positives).toContain("45 menit aktivitas tercatat di 3 hari");
  expect(r.adjustments).toEqual([{ goalId: goal.id, title: "Aktif 150 menit", goalType: "activity_minutes", fromTarget: 150, toTarget: 80, expectedVersion: 1, basis: "Dari catatanmu: 45 menit minggu ini." }]);
  expect(r.adjustments.some((x: any) => x.goalId === glucoseGoal.id)).toBe(false);
  expect(JSON.stringify(r)).not.toMatch(/mg\/dL|kkal/);
  expect(await interventionService.evaluate(a.id, { trigger: "WEEKLY_REVIEW_AVAILABLE" }, wib(realToday, 12))).toMatchObject({ option: "WEEKLY_REFLECTION", content: { action: "OPEN_REFLECTION" } });

  const body = { operationId: op(), weekStart: week, mood: "HARD", hardest: ["TIME"], note: "Lembur", adjustments: [{ goalId: goal.id, toTarget: 80 }], preferredSlot: "MORNING", rememberSlot: true };
  expect((await call("/api/me/coaching/checkins", a.token, { ...body, adjustments: [{ goalId: goal.id, toTarget: 10 }] })).status).toBe(422);
  expect((await call("/api/me/coaching/checkins", a.token, { ...body, adjustments: [{ goalId: glucoseGoal.id, toTarget: 3 }] })).status).toBe(422);
  expect((await call("/api/me/coaching/checkins", a.token, { ...body, weekStart: addDays(week, -7) })).status).toBe(422);
  const saved = await call("/api/me/coaching/checkins", a.token, body);
  expect(saved.status).toBe(201);
  const out = await J(saved);
  expect(out.recognition[0]).toBe("Refleksi minggu ini selesai");
  expect(out.checkin).toMatchObject({ weekStart: week, mood: "HARD", hardest: ["TIME"], preferredSlot: "MORNING", adjustments: [{ goalId: goal.id, fromTarget: 150, toTarget: 80 }] });
  expect(await J(await call("/api/me/coaching/checkins", a.token, body))).toMatchObject({ replayed: true });
  expect((await call("/api/me/coaching/checkins", a.token, { ...body, operationId: op() })).status).toBe(409);

  const g = await prisma.behaviorGoal.findUniqueOrThrow({ where: { id: goal.id } });
  expect([g.targetValue.toNumber(), g.version]).toEqual([80, 2]);
  expect(await prisma.recordRevision.findFirstOrThrow({ where: { goalId: goal.id } })).toMatchObject({ version: 1, reason: "Refleksi mingguan: target disesuaikan bersama pengguna" });
  expect((await prisma.behaviorGoal.findUniqueOrThrow({ where: { id: glucoseGoal.id } })).targetValue.toNumber()).toBe(7);
  expect(await prisma.memoryItem.findFirstOrThrow({ where: { userId: a.id, key: "ACTIVITY_TIME" } })).toMatchObject({ status: "ACTIVE", content: "Lebih suka beraktivitas pagi hari", sourceType: "USER" });
  expect((await prefs(a.id)).slot).toBe("MORNING");

  const after = await J(await call("/api/me/coaching/checkins", a.token));
  expect(after).toMatchObject({ done: { weekStart: week }, nudge: false, streak: 1, preferredSlot: "MORNING" });
  expect(await interventionService.evaluate(a.id, { trigger: "WEEKLY_REVIEW_AVAILABLE" }, wib(realToday, 14))).toMatchObject({ option: "NO_INTERVENTION", reason: "REVIEW_DONE", decision: "DO_NOT_INTERVENE" });

  const t = crypto.randomUUID();
  const chat = await J(await call(`/api/me/conversations/${t}/messages`, a.token, { clientMessageId: crypto.randomUUID(), text: "Minggu ini aku merasa gagal." }));
  const parts = chat.assistantMessage.parts as any[];
  expect(chat.assistantMessage.route).toBe("REFLECTION");
  expect(parts.find((p) => p.type === "reflection")).toMatchObject({ weekStart: week, done: true });
  expect(parts[0].text).toContain("tidak membuatmu gagal");

  const exp = await J(await call("/api/me/export", a.token));
  expect(exp.data.weeklyCheckins).toHaveLength(1);
  expect(Array.isArray(exp.data.coachingActions)).toBe(true);
});
