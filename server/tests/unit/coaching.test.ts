import { expect, test } from "bun:test";
import * as M from "../../src/features/coaching/coaching.model.ts";
import { classify, contentFor, decide, type PolicyInput } from "../../src/features/interventions/intervention.policy.ts";
import { routeMessage } from "../../src/features/conversation/conversation.router.ts";

const TODAY = "2026-11-12";
const facts = (over: Partial<M.Facts> = {}): M.Facts => ({
  today: TODAY,
  accountAgeDays: 30,
  mealsByDay: {},
  recordedDays7: 6,
  pastPlans: { planned: 0, notObserved: 0, done: 0, avgMinutes: null },
  goals: [],
  longestSessionMinutes: 30,
  memory: { availableMinutes: null, preferredSlot: null, dislikedTypes: [], used: [] },
  ...over,
});
const ctx = (prefs: M.SelectContext["prefs"] = {}, active: string[] = []): M.SelectContext => ({ prefs, activeSources: new Set(active) });
const mealDays = (n: number, withLunch: number) =>
  Object.fromEntries(Array.from({ length: n }, (_, i) => [M.addDays(TODAY, -(i + 1)), i < withLunch ? ["breakfast", "lunch", "dinner"] : ["breakfast", "dinner"]]));

test("Peluang makan siang: hanya dari catatan nyata, dengan bukti yang bisa diperiksa; hari ini tidak dihitung", () => {
  const f = facts({ mealsByDay: { ...mealDays(9, 2), [TODAY]: ["breakfast"] } });
  const { opportunities } = M.detectOpportunities(f, ctx());
  expect(opportunities).toHaveLength(1);
  const o = opportunities[0]!;
  expect(o).toMatchObject({ source: "MEAL_LOG_GAP", kind: "MEAL_LOGGING", days: 3, slot: "MIDDAY", params: { mealSlot: "lunch" }, title: "Catat makan siang 3 hari ke depan" });
  expect(o.evidence.summary).toBe("Makan siang tercatat di 2 dari 9 hari yang punya catatan makan.");
  expect(o.rationale).toContain("melewatkannya juga tidak apa-apa");
  expect(M.detectOpportunities(facts({ mealsByDay: mealDays(4, 0) }), ctx()).opportunities).toEqual([]);
  expect(M.detectOpportunities(facts({ mealsByDay: mealDays(9, 4) }), ctx()).opportunities).toEqual([]);
});

test("Kendali pengguna: dimatikan, ditunda, rencana sedang berjalan, dan varian yang ditolak menahan atau mengganti usulan", () => {
  const f = facts({ mealsByDay: mealDays(9, 1) });
  expect(M.detectOpportunities(f, ctx({ muted: ["MEAL_LOG_GAP"] })).withheld).toEqual([{ source: "MEAL_LOG_GAP", reason: "MUTED_BY_USER" }]);
  expect(M.detectOpportunities(f, ctx({ snoozed: { MEAL_LOG_GAP: "2026-11-14" } })).withheld[0]!.reason).toBe("SNOOZED");
  expect(M.detectOpportunities(f, ctx({ snoozed: { MEAL_LOG_GAP: "2026-11-12" } })).opportunities).toHaveLength(1);
  expect(M.detectOpportunities(f, ctx({}, ["MEAL_LOG_GAP"])).withheld[0]!.reason).toBe("PLAN_ALREADY_RUNNING");
  const smaller = M.detectOpportunities(f, ctx({ declinedVariants: { "MEAL_LOG_GAP:3d": 1 } })).opportunities[0]!;
  expect(smaller).toMatchObject({ variant: "1d", days: 1, title: "Catat makan siang hari ini", key: "MEAL_LOG_GAP:1d:lunch" });
  expect(M.detectOpportunities(f, ctx({ declinedVariants: { "MEAL_LOG_GAP:3d": 1, "MEAL_LOG_GAP:1d": 1 } })).withheld[0]!.reason).toBe("ALL_VARIANTS_DECLINED");
});

test("Rencana aktivitas yang sering belum terlihat: usulan lebih kecil, memakai ingatan, tidak melebihi sesi terpanjang, menghindari jenis yang tidak disukai", () => {
  const used = [{ id: "m1", content: "Punya waktu sekitar 10 menit untuk aktivitas", kind: "AVAILABLE_MINUTES" }, { id: "m2", content: "Kurang suka jalan kaki", kind: "ACTIVITY_DISLIKE" }];
  const f = facts({ pastPlans: { planned: 3, notObserved: 2, done: 1, avgMinutes: 30 }, memory: { availableMinutes: 10, preferredSlot: "MORNING", dislikedTypes: ["walking"], used } });
  const o = M.detectOpportunities(f, ctx()).opportunities[0]!;
  expect(o).toMatchObject({ source: "ACTIVITY_STEP_DOWN", params: { activityType: "cycling", durationMinutes: 10 }, slot: "MORNING", title: "Bersepeda 10 menit, 3 hari" });
  expect(o.evidence.summary).toBe("2 dari 3 rencana aktivitas terakhir belum terlihat di catatan.");
  expect(o.evidence.memories).toEqual(["Punya waktu sekitar 10 menit untuk aktivitas", "Kurang suka jalan kaki"]);
  const capped = M.detectOpportunities(facts({ pastPlans: { planned: 4, notObserved: 3, done: 1, avgMinutes: 60 }, longestSessionMinutes: 8 }), ctx()).opportunities[0]!;
  expect(capped.params.durationMinutes).toBe(10);
  expect(M.detectOpportunities(facts({ pastPlans: { planned: 3, notObserved: 1, done: 2, avgMinutes: 20 } }), ctx()).opportunities).toEqual([]);
});

test("Tujuan tertinggal: langkah kecil untuk tujuan pilihan pengguna; tujuan glukosa dan awal periode tidak dipakai", () => {
  const goal = (over: Partial<M.GoalFact>): M.GoalFact => ({ id: "g1", title: "Aktif 150 menit", goalType: "activity_minutes", period: "weekly", target: 150, value: 20, elapsedDays: 4, periodDays: 7, ...over });
  const o = M.detectOpportunities(facts({ goals: [goal({})], longestSessionMinutes: 25 }), ctx()).opportunities[0]!;
  expect(o).toMatchObject({ source: "GOAL_PACE", key: "GOAL_PACE:3d:g1", params: { activityType: "walking", durationMinutes: 25 }, days: 3 });
  expect(o.evidence.summary).toBe("Tujuan “Aktif 150 menit” baru 20 menit dari 150 menit di hari ke-4 dari 7.");
  expect(M.detectOpportunities(facts({ goals: [goal({ elapsedDays: 2 })] }), ctx()).opportunities).toEqual([]);
  expect(M.detectOpportunities(facts({ goals: [goal({ goalType: "record_glucose", target: 7, value: 0 })] }), ctx()).opportunities).toEqual([]);
  expect(M.detectOpportunities(facts({ goals: [goal({ value: 80 })] }), ctx()).opportunities).toEqual([]);
});

test("Mulai rutinitas: catatan jarang → satu catatan makan per hari; akun baru tidak langsung disarankan", () => {
  const o = M.detectOpportunities(facts({ recordedDays7: 1 }), ctx()).opportunities[0]!;
  expect(o).toMatchObject({ source: "ROUTINE_START", params: { mealSlot: null }, evidence: { summary: "Catatan ada di 1 dari 7 hari terakhir." } });
  expect(M.detectOpportunities(facts({ recordedDays7: 1, accountAgeDays: 1 }), ctx()).opportunities).toEqual([]);
});

test("Urutan memakai penilaian pengguna; jumlah usulan dibatasi dan sisanya dicatat sebagai ditahan", () => {
  const f = facts({ mealsByDay: mealDays(9, 1), pastPlans: { planned: 3, notObserved: 3, done: 0, avgMinutes: 20 } });
  expect(M.detectOpportunities(f, ctx()).opportunities.map((o) => o.source)).toEqual(["ACTIVITY_STEP_DOWN", "MEAL_LOG_GAP"]);
  expect(M.detectOpportunities(f, ctx({ usefulness: { MEAL_LOG_GAP: { helpful: 2, notHelpful: 0 } } })).opportunities[0]!.source).toBe("MEAL_LOG_GAP");
  const one = M.detectOpportunities(f, ctx({ maxSuggestions: 1 }));
  expect(one.opportunities).toHaveLength(1);
  expect(one.withheld).toContainEqual({ source: "MEAL_LOG_GAP", reason: "SUGGESTION_LIMIT" });
});

test("Validasi keselamatan: durasi di atas batas aman atau jenis yang tidak disukai ditolak", () => {
  const f = { longestSessionMinutes: 12, memory: { availableMinutes: null, preferredSlot: null, dislikedTypes: ["running"], used: [] } };
  expect(M.activityCap({ longestSessionMinutes: null })).toBe(10);
  expect(M.activityCap({ longestSessionMinutes: 90 })).toBe(30);
  expect(M.validateOpportunity({ kind: "ACTIVITY_SESSION", params: { activityType: "walking", durationMinutes: 15 }, days: 3 }, f)).toBe("DURATION_ABOVE_SAFE_CAP");
  expect(M.validateOpportunity({ kind: "ACTIVITY_SESSION", params: { activityType: "running", durationMinutes: 10 }, days: 3 }, f)).toBe("ACTIVITY_DISLIKED");
  expect(M.validateOpportunity({ kind: "ACTIVITY_SESSION", params: { activityType: "walking", durationMinutes: 10 }, days: 8 }, f)).toBe("DAYS_OUT_OF_RANGE");
  expect(M.validateOpportunity({ kind: "MEAL_LOGGING", params: { mealSlot: "lunch" }, days: 3 }, f)).toBeNull();
});

test("Status per hari: tercatat, dikonfirmasi sendiri, belum terlihat, hari ini, nanti; tanpa izin membaca catatan = tidak diketahui", () => {
  const rows: M.OutcomeRow[] = [{ localDate: "2026-11-09", status: "OBSERVED" }, { localDate: "2026-11-10", status: "USER_CONFIRMED" }];
  expect(M.dayStates("2026-11-09", 5, rows, TODAY, true).map((d) => d.state)).toEqual(["OBSERVED", "USER_CONFIRMED", "NOT_OBSERVED", "PLANNED", "PLANNED"]);
  expect(M.dayStates("2026-11-09", 5, rows, TODAY, true)[3]!.today).toBe(true);
  expect(M.dayStates("2026-11-09", 4, [], TODAY, false).map((d) => d.state)).toEqual(["UNKNOWN", "UNKNOWN", "UNKNOWN", "PLANNED"]);
  expect(M.matchesActivity({ activityType: "walking", durationMinutes: 10 }, { activityType: "walking", durationMinutes: 5 })).toBe(true);
  expect(M.matchesActivity({ activityType: "walking", durationMinutes: 10 }, { activityType: "walking", durationMinutes: 4 })).toBe(false);
  expect(M.matchesActivity({ activityType: "walking", durationMinutes: 10 }, { activityType: "cycling", durationMinutes: 30 })).toBe(false);
  expect(M.matchesMeal({ mealSlot: "lunch" }, "dinner")).toBe(false);
  expect(M.matchesMeal({ mealSlot: null }, "snack")).toBe(true);
});

test("Refleksi: minggu sasaran, pengamatan positif hanya tentang usaha, penyesuaian tujuan hanya menurunkan dan bukan untuk glukosa", () => {
  expect(M.reflectionWeekStart("2026-11-12", "2026-11-09")).toBe("2026-11-02");
  expect(M.reflectionWeekStart("2026-11-13", "2026-11-09")).toBe("2026-11-09");
  const pos = M.positiveObservations({ mealDays: 5, activityMinutes: 45, activityDays: 3, recordedDays: 6, totalDays: 7, actionsDone: 2, goalsReached: ["Catat makan"], previousReflection: true });
  expect(pos).toEqual(["Makan tercatat di 5 dari 7 hari", "45 menit aktivitas tercatat di 3 hari", "2 rencana kecil terlaksana", "Tujuan “Catat makan” tercapai", "Kamu menyelesaikan refleksi minggu lalu"]);
  expect(JSON.stringify(pos)).not.toMatch(/glukosa|kkal|kalori|mg\/dL/i);
  expect(M.positiveObservations({ mealDays: 1, activityMinutes: null, activityDays: 0, recordedDays: 1, totalDays: 7, actionsDone: 0, goalsReached: [], previousReflection: false })).toEqual([]);
  const g = (over: Partial<M.GoalWeek>): M.GoalWeek => ({ id: "g", title: "t", goalType: "activity_minutes", period: "weekly", target: 150, value: 45, version: 3, ...over });
  expect(M.goalAdjustments([g({})])).toEqual([{ goalId: "g", title: "t", goalType: "activity_minutes", fromTarget: 150, toTarget: 80, expectedVersion: 3, basis: "Dari catatanmu: 45 menit minggu ini." }]);
  expect(M.goalAdjustments([g({ goalType: "walking_sessions", target: 5, value: 1 })])[0]!.toTarget).toBe(3);
  expect(M.goalAdjustments([g({ goalType: "record_glucose", target: 7, value: 1 })])).toEqual([]);
  expect(M.goalAdjustments([g({ value: 100 })])).toEqual([]);
  expect(M.goalAdjustments([g({ value: null })])).toEqual([]);
  expect(M.goalAdjustments([g({ period: "daily" })])).toEqual([]);
  expect(M.recognitions({ streak: 3, actionsDone: 2, recordedDays: 5 })).toEqual(["Refleksi minggu ini selesai", "3 minggu berturut-turut", "2 rencana kecil terlaksana", "Data tercatat di 5 hari"]);
  expect(M.streakOf(["2026-11-09", "2026-11-02", "2026-10-19"], "2026-11-09")).toBe(2);
  expect(M.streakOf([], "2026-11-09")).toBe(0);
});

const base = (over: Partial<PolicyInput> = {}): PolicyInput => ({
  trigger: "COACHING_ACTION_DUE",
  nowMs: 1_800_000_000_000,
  localMinute: 10 * 60,
  consent: true,
  prefs: { pausedUntilMs: null, quietStartMinute: 22 * 60, quietEndMinute: 7 * 60, maxPerDay: 2, maxPerWeek: 7, mutedTriggers: [] },
  hasActiveGoal: false,
  context: { deliveredToday: 0, deliveredLast7Days: 0, lastDeliveredMs: null, sameKeyDeliveredMs: null, sameKeyRespondedToday: null, sameKeyUnrespondedWithinDays: false, snoozedUntilMs: null },
  coaching: { due: true, slotStarted: true, safe: true },
  ...over,
});

test("JITAI v2: lima kelas keputusan; tidak mengintervensi adalah hasil yang sah", () => {
  const card = decide(base());
  expect(card).toMatchObject({ option: "ACTION_REMINDER_CARD", coverage: "FULL" });
  expect(classify(card)).toBe("INTERVENE");
  const none = decide(base({ coaching: { due: false, slotStarted: true, safe: true } }));
  expect([none.reason, classify(none)]).toEqual(["NO_DUE_ACTION", "DO_NOT_INTERVENE"]);
  const review = decide(base({ coaching: { due: true, slotStarted: true, safe: false } }));
  expect([review.reason, classify(review)]).toEqual(["REQUIRES_REVIEW", "REQUIRES_REVIEW"]);
  const early = decide(base({ coaching: { due: true, slotStarted: false, safe: true } }));
  expect([early.reason, classify(early)]).toEqual(["SLOT_NOT_STARTED", "DEFER"]);
  expect(classify(decide(base({ localMinute: 23 * 60 })))).toBe("DEFER");
  const ask = decide(base({ recentNotUseful: true }));
  expect([ask.option, classify(ask)]).toEqual(["CLARIFICATION_QUESTION", "ASK_FOR_CLARIFICATION"]);
  expect(decide(base({ trigger: "WEEKLY_REVIEW_AVAILABLE", review: { done: true } }))).toMatchObject({ option: "NO_INTERVENTION", reason: "REVIEW_DONE" });
  expect(decide(base({ trigger: "WEEKLY_REVIEW_AVAILABLE", review: { done: false } })).option).toBe("WEEKLY_REFLECTION");
  expect(decide(base({ prefs: { ...base().prefs, mutedTriggers: ["COACHING_ACTION_DUE"] } })).reason).toBe("TRIGGER_MUTED");
  expect(contentFor("COACHING_ACTION_DUE", "Jalan kaki 10 menit · pagi")).toEqual({ title: "Rencana hari ini", body: "Jalan kaki 10 menit · pagi. Cukup langkah kecil.", action: "OPEN_COACHING" });
  expect(contentFor("WEEKLY_REVIEW_AVAILABLE").action).toBe("OPEN_REFLECTION");
});

test("Router: perasaan tentang minggu ini dan kata refleksi diarahkan ke refleksi; pertanyaan statistik dan berat badan tidak", () => {
  const r = (t: string) => routeMessage(t, { hasPreviousRun: false }).kind;
  expect(r("Minggu ini aku merasa gagal.")).toBe("REFLECTION");
  expect(r("minggu ini berat banget")).toBe("REFLECTION");
  expect(r("Mau refleksi mingguan")).toBe("REFLECTION");
  expect(r("pekan ini rencanaku nggak jalan")).toBe("REFLECTION");
  expect(r("Bagaimana aktivitasku minggu ini?")).toBe("STATS");
  expect(r("Aku susah konsisten")).toBe("SUPPORT");
  expect(r("berat badan minggu ini naik")).not.toBe("REFLECTION");
});
