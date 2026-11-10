import { isoWeekday, zonedToUtc } from "../medication/medication.model.ts";

export const REMINDER_KINDS = ["medication", "glucose", "meal", "activity", "goal", "custom"] as const;
export type ReminderKind = (typeof REMINDER_KINDS)[number];

export type ReminderRule = { id: string; kind: ReminderKind; localTime: string; daysOfWeek: number[]; enabled: boolean };
export type Occurrence = { reminderId: string; at: Date; localDate: string; localTime: string };

/**
 * Teks yang aman ditampilkan di layar kunci: tidak memuat nama obat atau nilai kesehatan.
 * Judul buatan pengguna hanya tampil di dalam aplikasi.
 */
export function lockScreenText(kind: ReminderKind): { title: string; body: string } {
  const body = "Buka beOkay untuk mencatat.";
  switch (kind) {
    case "medication": return { title: "Pengingat beOkay", body };
    case "glucose": return { title: "Pengingat beOkay", body };
    case "meal": return { title: "Pengingat beOkay", body: "Sudah waktunya mencatat makananmu?" };
    case "activity": return { title: "Pengingat beOkay", body: "Catat aktivitasmu hari ini." };
    case "goal": return { title: "Pengingat beOkay", body: "Cek tujuanmu hari ini." };
    default: return { title: "Pengingat beOkay", body };
  }
}

const dayMs = 86_400_000;
const addDays = (date: string, n: number) => new Date(Date.parse(date + "T00:00:00Z") + n * dayMs).toISOString().slice(0, 10);
const localDateOf = (instant: Date, timezone: string) =>
  new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit" }).format(instant);

/**
 * Kejadian berikutnya setelah `from` dalam `horizonDays` hari kalender lokal. Waktu lokal yang tidak ada
 * (celah DST) dimajukan oleh zonedToUtc; kejadian ganda pada hari yang sama tidak dibuat.
 */
export function upcomingOccurrences(rules: ReminderRule[], timezone: string, from: Date, horizonDays: number, limit = 200): Occurrence[] {
  const startDate = localDateOf(from, timezone);
  const out: Occurrence[] = [];
  for (let i = 0; i <= horizonDays; i++) {
    const date = addDays(startDate, i);
    const weekday = isoWeekday(date);
    for (const r of rules) {
      if (!r.enabled || !r.daysOfWeek.includes(weekday)) continue;
      const at = zonedToUtc(date, r.localTime, timezone);
      if (at.getTime() > from.getTime()) out.push({ reminderId: r.id, at, localDate: date, localTime: r.localTime });
    }
  }
  return out.sort((a, b) => a.at.getTime() - b.at.getTime() || a.reminderId.localeCompare(b.reminderId)).slice(0, limit);
}

export function nextOccurrence(rule: ReminderRule, timezone: string, from: Date): Occurrence | null {
  return upcomingOccurrences([rule], timezone, from, 8, 1)[0] ?? null;
}
