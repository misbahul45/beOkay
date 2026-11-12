import type { CoachingPrefs, CoachingSlot } from "../agent/personalization.ts";

export const COACHING_RULES_VERSION = "coach-rules-v2";
export const WINDOW_DAYS = 14;
export const PROPOSAL_TTL_MS = 3 * 86_400_000;
export const SNOOZE_DAYS = { DECLINE: 3, NOT_NOW: 3, ALREADY_DONE: 7, TOO_FREQUENT: 3 } as const;
export const MIN_ACTIVITY_FRACTION = 0.5;
export const DEFAULT_MAX_SUGGESTIONS = 2;

export type Source = "MEAL_LOG_GAP" | "ACTIVITY_STEP_DOWN" | "GOAL_PACE" | "ROUTINE_START" | "PROBLEM_SOLVING";
export type Kind = "ACTIVITY_SESSION" | "MEAL_LOGGING" | "HABIT_STEP";
export type MealSlot = "breakfast" | "lunch" | "dinner";
export type DayState = "PLANNED" | "OBSERVED" | "USER_CONFIRMED" | "NOT_OBSERVED" | "RETRACTED" | "UNKNOWN";
export type { CoachingSlot };

export const SLOTS: readonly CoachingSlot[] = ["MORNING", "MIDDAY", "AFTERNOON", "EVENING"];
export const SLOT_LABEL: Record<CoachingSlot, string> = { MORNING: "pagi", MIDDAY: "siang", AFTERNOON: "sore", EVENING: "malam" };
export const SLOT_TIME: Record<CoachingSlot, string> = { MORNING: "07:00", MIDDAY: "12:00", AFTERNOON: "16:00", EVENING: "19:00" };
export const SLOT_START_MINUTE: Record<CoachingSlot, number> = { MORNING: 360, MIDDAY: 660, AFTERNOON: 900, EVENING: 1080 };
export const SLOT_FROM_WORD: Record<string, CoachingSlot> = { pagi: "MORNING", siang: "MIDDAY", sore: "AFTERNOON", malam: "EVENING" };

const MEAL_LABEL: Record<MealSlot, string> = { breakfast: "sarapan", lunch: "makan siang", dinner: "makan malam" };
const MEAL_SLOT_TIME: Record<MealSlot, CoachingSlot> = { breakfast: "MORNING", lunch: "MIDDAY", dinner: "EVENING" };
export const ACTIVITY_LABEL: Record<string, string> = { walking: "Jalan kaki", cycling: "Bersepeda", running: "Lari", strength: "Latihan kekuatan", other: "Aktivitas ringan" };
const ACTIVITY_ORDER = ["walking", "cycling", "strength", "other"];
const ADJUSTABLE_GOALS = new Set(["activity_minutes", "walking_sessions", "record_meals", "manual_checkins"]);

export type GoalFact = { id: string; title: string; goalType: string; period: string; target: number; value: number | null; elapsedDays: number; periodDays: number };

export type Facts = {
  today: string;
  accountAgeDays: number;
  mealsByDay: Record<string, string[]>;
  recordedDays7: number;
  pastPlans: { planned: number; notObserved: number; done: number; avgMinutes: number | null };
  goals: GoalFact[];
  longestSessionMinutes: number | null;
  memory: { availableMinutes: number | null; preferredSlot: CoachingSlot | null; dislikedTypes: string[]; used: { id: string; content: string; kind: string }[]; unwell?: boolean; avoidSlots?: string[] };
};

export type ActionParams = { activityType?: string; durationMinutes?: number; mealSlot?: MealSlot | null };

export type Opportunity = {
  key: string;
  source: Source;
  variant: string;
  kind: Kind;
  title: string;
  rationale: string;
  evidence: { summary: string; window: string; memories: string[]; [k: string]: unknown };
  params: ActionParams;
  days: number;
  slot: CoachingSlot | null;
  priority: number;
};

export const addDays = (date: string, n: number) => new Date(Date.parse(date + "T00:00:00Z") + n * 86_400_000).toISOString().slice(0, 10);
export const daysBetween = (from: string, to: string) => Math.round((Date.parse(to + "T00:00:00Z") - Date.parse(from + "T00:00:00Z")) / 86_400_000);
export const isoWeekdayOf = (date: string) => new Date(date + "T00:00:00Z").getUTCDay() || 7;
const round5 = (n: number) => Math.max(5, Math.round(n / 5) * 5);
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

export function activityCap(f: Pick<Facts, "longestSessionMinutes">): number {
  return clamp(Math.max(10, f.longestSessionMinutes ?? 0), 10, 30);
}

function pickActivity(disliked: string[]): string | null {
  return ACTIVITY_ORDER.find((t) => !disliked.includes(t)) ?? null;
}

function activityTitle(type: string, minutes: number, days: number) {
  return `${ACTIVITY_LABEL[type] ?? "Aktivitas"} ${minutes} menit${days > 1 ? `, ${days} hari` : " hari ini"}`;
}

type Variant = Omit<Opportunity, "key" | "source" | "priority">;

function mealGap(f: Facts): { subject: string; variants: Variant[] } | null {
  const past = Object.entries(f.mealsByDay).filter(([d, cats]) => d < f.today && cats.length > 0);
  if (past.length < 5) return null;
  let best: { slot: MealSlot; count: number; ratio: number } | null = null;
  for (const slot of ["lunch", "breakfast", "dinner"] as MealSlot[]) {
    const count = past.filter(([, cats]) => cats.includes(slot)).length;
    const ratio = count / past.length;
    if (ratio <= 0.3 && (!best || ratio < best.ratio)) best = { slot, count, ratio };
  }
  if (!best) return null;
  const label = MEAL_LABEL[best.slot];
  const cap = label.charAt(0).toUpperCase() + label.slice(1);
  const evidence = { summary: `${cap} tercatat di ${best.count} dari ${past.length} hari yang punya catatan makan.`, window: `${WINDOW_DAYS} hari terakhir`, memories: [], mealSlot: best.slot, slotDays: best.count, mealDays: past.length };
  const rationale = `Hanya bila kamu memang ${label}; melewatkannya juga tidak apa-apa. Catatan yang lengkap membuat ringkasanmu lebih bisa dipercaya.`;
  const base = { kind: "MEAL_LOGGING" as const, rationale, evidence, params: { mealSlot: best.slot }, slot: MEAL_SLOT_TIME[best.slot] };
  return {
    subject: best.slot,
    variants: [
      { ...base, variant: "3d", title: `Catat ${label} 3 hari ke depan`, days: 3 },
      { ...base, variant: "1d", title: `Catat ${label} hari ini`, days: 1 },
    ],
  };
}

function stepDown(f: Facts): { subject: string; variants: Variant[] } | null {
  const p = f.pastPlans;
  if (p.planned < 2 || p.notObserved < 2 || p.notObserved < p.done) return null;
  const type = pickActivity(f.memory.dislikedTypes);
  if (!type) return null;
  const cap = activityCap(f);
  const base = p.avgMinutes ? Math.round(p.avgMinutes / 2) : 10;
  const minutes = round5(Math.min(base, f.memory.availableMinutes ?? base, cap));
  const memories = f.memory.used.filter((m) => m.kind === "AVAILABLE_MINUTES" || m.kind === "ACTIVITY_TIME" || m.kind === "ACTIVITY_DISLIKE").map((m) => m.content);
  const evidence = { summary: `${p.notObserved} dari ${p.planned} rencana aktivitas terakhir belum terlihat di catatan.`, window: `${WINDOW_DAYS} hari terakhir`, memories, planned: p.planned, notObserved: p.notObserved };
  const rationale = "Lebih kecil dari rencana sebelumnya supaya lebih mudah dijalankan. Durasi tidak melebihi sesi terpanjangmu.";
  const v = { kind: "ACTIVITY_SESSION" as const, rationale, evidence, params: { activityType: type, durationMinutes: minutes }, slot: f.memory.preferredSlot };
  return {
    subject: type,
    variants: [
      { ...v, variant: "3d", title: activityTitle(type, minutes, 3), days: 3 },
      { ...v, variant: "1d", title: activityTitle(type, minutes, 1), days: 1 },
    ],
  };
}

function valueText(goalType: string, v: number) {
  if (goalType === "activity_minutes") return `${v} menit`;
  if (goalType === "daily_steps") return `${v} langkah`;
  if (goalType === "walking_sessions") return `${v} sesi`;
  return `${v} hari`;
}

function goalPace(f: Facts): { subject: string; variants: Variant[] } | null {
  const behind = f.goals
    .filter((g) => g.period === "weekly" && ["activity_minutes", "walking_sessions", "record_meals"].includes(g.goalType) && g.elapsedDays >= 3 && g.elapsedDays < g.periodDays)
    .map((g) => {
      const value = g.value ?? 0;
      const expected = (g.target * g.elapsedDays) / g.periodDays;
      return { g, value, gap: expected - value, behind: value < expected * 0.5 };
    })
    .filter((x) => x.behind)
    .sort((a, b) => b.gap / b.g.target - a.gap / a.g.target);
  const hit = behind[0];
  if (!hit) return null;
  const { g, value } = hit;
  const remaining = g.periodDays - g.elapsedDays + 1;
  const days = Math.max(1, Math.min(3, remaining));
  const evidence = { summary: `Tujuan “${g.title}” baru ${valueText(g.goalType, value)} dari ${valueText(g.goalType, g.target)} di hari ke-${g.elapsedDays} dari ${g.periodDays}.`, window: "periode tujuan ini", memories: [] as string[], goalId: g.id, value, target: g.target };
  if (g.goalType === "record_meals") {
    const v = { kind: "MEAL_LOGGING" as const, rationale: "Langkah kecil untuk tujuan yang kamu pilih sendiri. Tujuannya tidak diubah.", evidence, params: { mealSlot: null }, slot: null };
    return { subject: g.id, variants: [{ ...v, variant: `${days}d`, title: days > 1 ? `Catat satu kali makan, ${days} hari` : "Catat satu kali makan hari ini", days }] };
  }
  const type = g.goalType === "walking_sessions" ? "walking" : pickActivity(f.memory.dislikedTypes);
  if (!type) return null;
  const cap = activityCap(f);
  const want = g.goalType === "activity_minutes" ? (g.target - value) / remaining : 10;
  const minutes = round5(Math.min(Math.max(want, 5), f.memory.availableMinutes ?? cap, cap));
  evidence.memories = f.memory.used.filter((m) => m.kind === "AVAILABLE_MINUTES" || m.kind === "ACTIVITY_TIME").map((m) => m.content);
  const v = { kind: "ACTIVITY_SESSION" as const, rationale: "Langkah kecil untuk tujuan yang kamu pilih sendiri. Tujuannya tidak diubah; durasi tidak melebihi sesi terpanjangmu.", evidence, params: { activityType: type, durationMinutes: minutes }, slot: f.memory.preferredSlot };
  return { subject: g.id, variants: [{ ...v, variant: `${days}d`, title: activityTitle(type, minutes, days), days }] };
}

function routineStart(f: Facts): { subject: string; variants: Variant[] } | null {
  if (f.recordedDays7 > 2 || f.accountAgeDays < 3) return null;
  const evidence = { summary: `Catatan ada di ${f.recordedDays7} dari 7 hari terakhir.`, window: "7 hari terakhir", memories: [], recordedDays: f.recordedDays7 };
  const base = { kind: "MEAL_LOGGING" as const, rationale: "Mulai dari yang paling mudah: satu catatan sehari sudah membantu.", evidence, params: { mealSlot: null }, slot: null };
  return {
    subject: "any",
    variants: [
      { ...base, variant: "3d", title: "Catat satu kali makan per hari, 3 hari", days: 3 },
      { ...base, variant: "1d", title: "Catat satu kali makan hari ini", days: 1 },
    ],
  };
}

const RULES: [Source, number, (f: Facts) => { subject: string; variants: Variant[] } | null][] = [
  ["ROUTINE_START", 1, routineStart],
  ["GOAL_PACE", 2, goalPace],
  ["ACTIVITY_STEP_DOWN", 3, stepDown],
  ["MEAL_LOG_GAP", 4, mealGap],
];

export type SelectContext = { prefs: CoachingPrefs; activeSources: ReadonlySet<string> };
export type Selection = { opportunities: Opportunity[]; withheld: { source: Source; reason: string }[] };

export function validateOpportunity(o: Pick<Opportunity, "kind" | "params" | "days">, f: Pick<Facts, "longestSessionMinutes" | "memory">): string | null {
  if (o.days < 1 || o.days > 7) return "DAYS_OUT_OF_RANGE";
  if (o.kind === "ACTIVITY_SESSION") {
    const m = o.params.durationMinutes ?? 0;
    if (m < 5 || m > activityCap(f)) return "DURATION_ABOVE_SAFE_CAP";
    if (!o.params.activityType || f.memory.dislikedTypes.includes(o.params.activityType)) return "ACTIVITY_DISLIKED";
  }
  return null;
}

export function detectOpportunities(f: Facts, ctx: SelectContext): Selection {
  const withheld: Selection["withheld"] = [];
  const out: Opportunity[] = [];
  const muted = new Set(ctx.prefs.muted ?? []);
  const snoozed = ctx.prefs.snoozed ?? {};
  const declined = ctx.prefs.declinedVariants ?? {};
  const routine = routineStart(f) !== null;
  for (const [source, priority, rule] of RULES) {
    if (source === "MEAL_LOG_GAP" && routine) continue;
    const found = rule(f);
    if (!found) continue;
    if (muted.has(source)) { withheld.push({ source, reason: "MUTED_BY_USER" }); continue; }
    if (snoozed[source] && snoozed[source]! > f.today) { withheld.push({ source, reason: "SNOOZED" }); continue; }
    if (ctx.activeSources.has(source)) { withheld.push({ source, reason: "PLAN_ALREADY_RUNNING" }); continue; }
    const variant = found.variants.find((v) => !declined[`${source}:${v.variant}`]);
    if (!variant) { withheld.push({ source, reason: "ALL_VARIANTS_DECLINED" }); continue; }
    if (variant.kind === "ACTIVITY_SESSION" && f.memory.unwell) { withheld.push({ source, reason: "TEMPORARY_CONDITION" }); continue; }
    const unsafe = validateOpportunity(variant, f);
    if (unsafe) { withheld.push({ source, reason: unsafe }); continue; }
    const slot = variant.slot && f.memory.avoidSlots?.includes(variant.slot) ? null : variant.slot;
    out.push({ ...variant, slot, key: `${source}:${variant.variant}:${found.subject}`, source, priority });
  }
  const score = (s: Source) => {
    const u = ctx.prefs.usefulness?.[s];
    return u ? u.helpful - u.notHelpful : 0;
  };
  out.sort((a, b) => score(b.source) - score(a.source) || a.priority - b.priority);
  const limit = ctx.prefs.maxSuggestions ?? DEFAULT_MAX_SUGGESTIONS;
  for (const o of out.slice(limit)) withheld.push({ source: o.source, reason: "SUGGESTION_LIMIT" });
  return { opportunities: out.slice(0, limit), withheld };
}

export const actionDates = (startDate: string, days: number) => Array.from({ length: days }, (_, i) => addDays(startDate, i));

export type OutcomeRow = { localDate: string; status: "OBSERVED" | "USER_CONFIRMED" | "RETRACTED" };

export function dayStates(startDate: string, days: number, outcomes: OutcomeRow[], today: string, canObserve: boolean): { date: string; state: DayState; today: boolean }[] {
  const byDate = new Map(outcomes.map((o) => [o.localDate, o.status]));
  return actionDates(startDate, days).map((date) => {
    const row = byDate.get(date);
    const isToday = date === today;
    if (row) return { date, state: row, today: isToday };
    if (date >= today) return { date, state: "PLANNED", today: isToday };
    return { date, state: canObserve ? "NOT_OBSERVED" : "UNKNOWN", today: false };
  });
}

export function matchesActivity(params: ActionParams, s: { activityType: string; durationMinutes: number }): boolean {
  if (params.activityType && params.activityType !== s.activityType) return false;
  return s.durationMinutes >= (params.durationMinutes ?? 0) * MIN_ACTIVITY_FRACTION;
}

export function matchesMeal(params: ActionParams, category: string): boolean {
  return !params.mealSlot || params.mealSlot === category;
}

export function reflectionWeekStart(today: string, currentWeekStart: string): string {
  return daysBetween(currentWeekStart, today) >= 4 ? currentWeekStart : addDays(currentWeekStart, -7);
}

export type WeekFacts = {
  mealDays: number;
  activityMinutes: number | null;
  activityDays: number;
  recordedDays: number;
  totalDays: number;
  actionsDone: number;
  goalsReached: string[];
  previousReflection: boolean;
};

export function positiveObservations(w: WeekFacts): string[] {
  const out: string[] = [];
  if (w.mealDays >= 3) out.push(`Makan tercatat di ${w.mealDays} dari ${w.totalDays} hari`);
  if ((w.activityMinutes ?? 0) > 0) out.push(`${w.activityMinutes} menit aktivitas tercatat di ${w.activityDays} hari`);
  if (w.actionsDone > 0) out.push(`${w.actionsDone} rencana kecil terlaksana`);
  for (const g of w.goalsReached) out.push(`Tujuan “${g}” tercapai`);
  if (w.previousReflection) out.push("Kamu menyelesaikan refleksi minggu lalu");
  return out;
}

export type GoalWeek = { id: string; title: string; goalType: string; period: string; target: number; value: number | null; version: number; history?: (number | null)[] };
export type Adjustment = { goalId: string; title: string; goalType: string; fromTarget: number; toTarget: number; expectedVersion: number; basis: string; direction: "UP" | "DOWN" };

export const MAX_WEEKLY_INCREASE = 0.1;
export const UP_PERCENTILE = 0.6;
const COUNT_GOALS = new Set(["walking_sessions", "record_meals", "manual_checkins"]);

function niceTarget(goalType: string, v: number): number {
  if (goalType === "activity_minutes") return Math.max(10, Math.round(v / 10) * 10);
  if (goalType === "record_meals") return clamp(Math.round(v), 1, 7);
  return Math.max(1, Math.round(v));
}

export function percentile(values: number[], p: number): number {
  const s = [...values].sort((a, b) => a - b);
  if (s.length === 0) return NaN;
  const idx = (s.length - 1) * p;
  const lo = Math.floor(idx), hi = Math.ceil(idx);
  return s[lo]! + (s[hi]! - s[lo]!) * (idx - lo);
}

export function raisedTarget(goalType: string, target: number, p60: number): number | null {
  if (COUNT_GOALS.has(goalType)) {
    const max = goalType === "record_meals" ? 7 : Number.POSITIVE_INFINITY;
    const to = Math.min(Math.floor(p60), target + 1, max);
    return to > target ? to : null;
  }
  const to = Math.floor(Math.min(p60, target * (1 + MAX_WEEKLY_INCREASE)) / 5) * 5;
  return to > target ? to : null;
}

export function goalAdjustments(goals: GoalWeek[]): Adjustment[] {
  const out: Adjustment[] = [];
  for (const g of goals) {
    if (g.period !== "weekly" || !ADJUSTABLE_GOALS.has(g.goalType) || g.value === null) continue;
    const ratio = g.value / g.target;
    if (ratio < 0.6) {
      const to = niceTarget(g.goalType, Math.max(g.value * 1.2, g.target * 0.5));
      if (to < g.target) out.push({ goalId: g.id, title: g.title, goalType: g.goalType, fromTarget: g.target, toTarget: to, expectedVersion: g.version, basis: `Dari catatanmu: ${valueText(g.goalType, g.value)} minggu ini.`, direction: "DOWN" });
      continue;
    }
    const weeks = [g.value, ...(g.history ?? [])].filter((v): v is number => v !== null);
    if (ratio < 1 || weeks.length < 3) continue;
    const reached = weeks.filter((v) => v >= g.target).length;
    if (reached < 2) continue;
    const to = raisedTarget(g.goalType, g.target, percentile(weeks, UP_PERCENTILE));
    if (to === null) continue;
    out.push({ goalId: g.id, title: g.title, goalType: g.goalType, fromTarget: g.target, toTarget: to, expectedVersion: g.version, basis: `Tercapai di ${reached} dari ${weeks.length} minggu terakhir (${weeks.map((v) => valueText(g.goalType, v)).join(", ")}). Naik paling banyak 10% per minggu; boleh kamu tolak.`, direction: "UP" });
  }
  return out;
}

export const STEPS_WINDOW_DAYS = 10;

export function dailyStepsAdjustment(g: { id: string; title: string; target: number; version: number }, last: (number | null)[]): Adjustment | null {
  const values = last.filter((v): v is number => v !== null);
  if (values.length < 5) return null;
  const p60 = percentile(values, UP_PERCENTILE);
  const reached = values.filter((v) => v >= g.target).length;
  const round100 = (v: number) => Math.floor(v / 100) * 100;
  const basis = `${values.length} hari dengan data langkah dalam ${STEPS_WINDOW_DAYS} hari terakhir; persentil ke-60: ${Math.round(p60)} langkah.`;
  if (reached >= Math.ceil(values.length * 0.6) && p60 > g.target) {
    const to = round100(Math.min(p60, g.target * (1 + MAX_WEEKLY_INCREASE)));
    if (to > g.target) return { goalId: g.id, title: g.title, goalType: "daily_steps", fromTarget: g.target, toTarget: to, expectedVersion: g.version, basis: `${basis} Naik paling banyak 10%; boleh kamu tolak.`, direction: "UP" };
  }
  if (p60 < g.target * 0.6) {
    const to = Math.max(1000, Math.ceil(Math.max(p60, g.target * (1 - MAX_WEEKLY_INCREASE)) / 100) * 100);
    if (to < g.target) return { goalId: g.id, title: g.title, goalType: "daily_steps", fromTarget: g.target, toTarget: to, expectedVersion: g.version, basis: `${basis} Turun paling banyak 10% per minggu.`, direction: "DOWN" };
  }
  return null;
}

export function recognitions(input: { streak: number; actionsDone: number; recordedDays: number }): string[] {
  const out = ["Refleksi mingguan selesai"];
  if (input.streak >= 2) out.push(`${input.streak} minggu berturut-turut`);
  if (input.actionsDone > 0) out.push(`${input.actionsDone} rencana kecil terlaksana`);
  if (input.recordedDays >= 4) out.push(`Data tercatat di ${input.recordedDays} hari`);
  return out;
}

export function streakOf(weekStarts: string[], target: string): number {
  const set = new Set(weekStarts);
  let n = 0;
  for (let w = target; set.has(w); w = addDays(w, -7)) n++;
  return n;
}
