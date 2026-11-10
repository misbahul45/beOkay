/**
 * Kebijakan keputusan intervensi: fungsi MURNI (tanpa DB, tanpa LLM, tanpa jaringan) sehingga dapat diuji dan diaudit.
 * "Tidak mengintervensi" adalah hasil yang sah dan umum. Angka awal adalah hipotesis produk, bukan batas klinis.
 */
export const INTERVENTION_POLICY_VERSION = "jitai-policy-v1";

export const TRIGGERS = ["USER_REQUESTS_SUPPORT", "GOAL_WINDOW_APPROACHING", "USER_SELECTED_ROUTINE_REMINDER", "WEEKLY_REVIEW_AVAILABLE"] as const;
export type Trigger = (typeof TRIGGERS)[number];
export type Option = "NO_INTERVENTION" | "IN_APP_SUGGESTION" | "GOAL_REVIEW_CARD" | "WEEKLY_REFLECTION";

/** Dimulai pengguna: boleh tampil di jam tenang dan tidak memakai jatah proaktif (pengguna sendiri yang meminta). */
export const USER_INITIATED: ReadonlySet<Trigger> = new Set(["USER_REQUESTS_SUPPORT"]);
export const MIN_GAP_MS = 3 * 3_600_000;
export const DUPLICATE_WINDOW_MS = 12 * 3_600_000;
export const REPEAT_SUPPRESS_DAYS = 2;
export const EXPIRY_MS = 12 * 3_600_000;

export type PolicyInput = {
  trigger: Trigger;
  nowMs: number;
  localMinute: number; // menit sejak tengah malam, zona waktu pengguna saat ini
  consent: boolean;
  prefs: { pausedUntilMs: number | null; quietStartMinute: number; quietEndMinute: number; maxPerDay: number; maxPerWeek: number; mutedTriggers: readonly string[] };
  hasActiveGoal: boolean; // relevan untuk trigger tujuan
  context: { deliveredToday: number; deliveredLast7Days: number; lastDeliveredMs: number | null; sameKeyDeliveredMs: number | null; sameKeyRespondedToday: "ALREADY_DONE" | "OTHER" | null; sameKeyUnrespondedWithinDays: boolean; snoozedUntilMs: number | null };
};

export type PolicyResult = { option: Option; reason: string | null; coverage: "FULL" | "PARTIAL" | "NONE" };

export function inQuietHours(minute: number, start: number, end: number): boolean {
  if (start === end) return false; // tidak ada jam tenang
  return start < end ? minute >= start && minute < end : minute >= start || minute < end; // melewati tengah malam
}

const none = (reason: string, coverage: PolicyResult["coverage"] = "NONE"): PolicyResult => ({ option: "NO_INTERVENTION", reason, coverage });

export function decide(i: PolicyInput): PolicyResult {
  // 1. Persetujuan: tanpa ini tidak ada apa pun yang diproses.
  if (!i.consent) return none("CONSENT_MISSING");
  const userInitiated = USER_INITIATED.has(i.trigger);

  // 2. Kendali pengguna: jeda dan jenis yang dimatikan menghentikan intervensi PROAKTIF (permintaan sendiri tetap dilayani).
  if (!userInitiated) {
    if (i.prefs.pausedUntilMs !== null && i.prefs.pausedUntilMs > i.nowMs) return none("COACHING_PAUSED");
    if (i.prefs.mutedTriggers.includes(i.trigger)) return none("TRIGGER_MUTED");
  } else if (i.prefs.mutedTriggers.includes(i.trigger)) {
    return none("TRIGGER_MUTED");
  }

  // 3. Kelayakan khusus pemicu. Tidak ada data = pesan netral, bukan tebakan.
  const needsGoal = i.trigger === "GOAL_WINDOW_APPROACHING" || i.trigger === "USER_SELECTED_ROUTINE_REMINDER";
  if (needsGoal && !i.hasActiveGoal) return none("NO_ACTIVE_GOAL");
  const coverage: PolicyResult["coverage"] = needsGoal ? "FULL" : "PARTIAL";

  // 4. Sudah dikerjakan / sudah ditunda / sudah dikirim: jangan ulang.
  if (i.context.sameKeyRespondedToday === "ALREADY_DONE") return none("ALREADY_DONE_TODAY", coverage);
  if (i.context.snoozedUntilMs !== null && i.context.snoozedUntilMs > i.nowMs) return none("SNOOZED", coverage);
  if (i.context.sameKeyDeliveredMs !== null && i.nowMs - i.context.sameKeyDeliveredMs < DUPLICATE_WINDOW_MS) return none("DUPLICATE", coverage);

  if (!userInitiated) {
    // 5. Tidak ada eskalasi karena diam: pesan sama yang belum ditanggapi tidak diulang dalam beberapa hari.
    if (i.context.sameKeyUnrespondedWithinDays) return none("REPEAT_SUPPRESSED", coverage);
    // 6. Jam tenang dan jatah/jeda minimum.
    if (inQuietHours(i.localMinute, i.prefs.quietStartMinute, i.prefs.quietEndMinute)) return none("QUIET_HOURS", coverage);
    if (i.context.deliveredToday >= i.prefs.maxPerDay) return none("DAILY_LIMIT", coverage);
    if (i.context.deliveredLast7Days >= i.prefs.maxPerWeek) return none("WEEKLY_LIMIT", coverage);
    if (i.context.lastDeliveredMs !== null && i.nowMs - i.context.lastDeliveredMs < MIN_GAP_MS) return none("TOO_SOON", coverage);
  }

  const option: Option = i.trigger === "WEEKLY_REVIEW_AVAILABLE" ? "WEEKLY_REFLECTION" : needsGoal ? "GOAL_REVIEW_CARD" : "IN_APP_SUGGESTION";
  return { option, reason: null, coverage };
}

/** Isi pesan dari daftar tetap (bukan LLM): netral, tanpa klaim kesehatan, dengan tindakan yang jelas. */
export function contentFor(trigger: Trigger, goalTitle?: string): { title: string; body: string; action: "OPEN_COACH" | "OPEN_GOALS" | "OPEN_INSIGHTS" } {
  switch (trigger) {
    case "USER_REQUESTS_SUPPORT":
      return { title: "Satu langkah kecil hari ini?", body: "Mau cari satu pilihan makan atau aktivitas yang pas untukmu?", action: "OPEN_COACH" };
    case "GOAL_WINDOW_APPROACHING":
      return { title: "Tujuanmu", body: `${goalTitle ?? "Tujuanmu"}: mau catat check-in hari ini?`, action: "OPEN_GOALS" };
    case "USER_SELECTED_ROUTINE_REMINDER":
      return { title: "Rutinitas pilihanmu", body: `Waktunya ${goalTitle ?? "rutinitas yang kamu pilih"}.`, action: "OPEN_GOALS" };
    case "WEEKLY_REVIEW_AVAILABLE":
      return { title: "Ringkasan minggumu", body: "Ringkasan minggu ini siap dilihat.", action: "OPEN_INSIGHTS" };
  }
}
