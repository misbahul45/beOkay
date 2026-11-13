import type { Statistic } from "../insights/statistics.model.ts";
import type { StatsDays, StatsDomain } from "./conversation.router.ts";

export type Suggestion = { label: string; message: string };

export type Part =
  | { type: "text"; text: string }
  | { type: "statistic"; statisticId: string; domain: StatsDomain; label: string; value: number | null; unit: string | null; caption: string; days: StatsDays }
  | { type: "recommendations"; runId: string; kind: "NUTRITION" | "ACTIVITY"; recommendationIds: string[] }
  | { type: "no_match"; query: string; text: string }
  | { type: "safety"; code: string; title: string; text: string; urgent: boolean }
  | { type: "notice"; tone: "info" | "warning" | "error"; text: string }
  | { type: "consent_required"; purpose: string; text: string }
  | { type: "suggestions"; items: Suggestion[] }
  | { type: "link"; label: string; target: LinkTarget }
  | { type: "meal_draft"; draftId: string }
  | { type: "memory_proposal"; memoryId: string }
  | { type: "photo"; items: { name: string; confidence: "high" | "medium" | "low" }[] }
  | { type: "reflection"; weekStart: string; positives: string[]; actionsDone: number; canAdjust: boolean; done: boolean }
  | { type: "challenges"; items: ChallengeItem[] }
  | { type: "education"; items: { key: string; title: string; readMinutes: number; reviewStatus: "DRAFT" | "REVIEWED" }[] };

export type ChallengeItem = { id: string; title: string; communityName: string; startsOn: string; endsOn: string; status: string; statusLabel: string; participating: boolean; progress: { activeDays: number; targetDays: number } | null };

export type BasisSource = { kind: "KNOWLEDGE" | "STATISTICS" | "FOOD_REFERENCE" | "USER_CATALOG" | "FOOD_PREFERENCES" | "ACTIVITY_HISTORY" | "GOALS" | "SAFETY_POLICY" | "MESSAGE" | "PHOTO" | "PORTION_MEASURES" | "LANGUAGE_MODEL"; label: string };
export type Basis = { sources: BasisSource[]; memories: { id: string; content: string }[]; certainty?: string; skill?: unknown; secondarySkills?: unknown[]; denial?: unknown };

export type LinkTarget = "INSIGHTS" | "LOG" | "LOG_MEAL" | "CONSENT" | "COMMUNITY" | "GOALS";

export const STARTERS: Suggestion[] = [
  { label: "Bagaimana aktivitasku minggu ini?", message: "Bagaimana aktivitasku minggu ini?" },
  { label: "Cari info nasi goreng", message: "Cari info nasi goreng" },
  { label: "Ide olahraga 15 menit", message: "Ide olahraga ringan 15 menit" },
  { label: "Aku susah konsisten", message: "Aku susah konsisten" },
];

export const text = (t: string): Part => ({ type: "text", text: t });
export const suggestions = (items: Suggestion[]): Part => ({ type: "suggestions", items });

const fmt = (n: number, digits = 0) => n.toLocaleString("id-ID", { maximumFractionDigits: digits, minimumFractionDigits: 0 });
const byId = (stats: Statistic[], id: string) => stats.find((s) => s.id === id);
const READY = (s: Statistic | undefined): s is Statistic & { value: number } => !!s && s.state === "READY" && s.value !== null;

function changeSentence(s: Statistic, days: number, unit: string, digits = 0): string | null {
  if (!s.comparison) return null;
  const c = s.comparison.change;
  if (c === 0) return `Sama dengan ${days} hari sebelumnya.`;
  return `Itu ${fmt(Math.abs(c), digits)} ${unit} lebih ${c > 0 ? "banyak" : "sedikit"} dari ${days} hari sebelumnya.`;
}

const statPart = (domain: StatsDomain, days: StatsDays, s: Statistic, label: string, caption: string): Part => ({
  type: "statistic",
  statisticId: s.id,
  domain,
  label,
  value: s.value,
  unit: s.unit,
  caption,
  days,
});

export function statisticsReply(domain: StatsDomain, days: StatsDays, stats: Statistic[], glucoseUnit: string): Part[] {
  const trends: Part = { type: "link", label: "Lihat tren", target: "INSIGHTS" };
  if (domain === "activity") {
    const total = byId(stats, "activity.total_minutes");
    const active = byId(stats, "activity.active_days");
    if (!READY(total) || total.value === 0) {
      return [text(`Belum ada aktivitas tercatat dalam ${days} hari terakhir. Hari tanpa catatan belum tentu hari tanpa gerak.`), suggestions([{ label: "Ide aktivitas 10 menit", message: "Ide olahraga ringan 10 menit" }]), trends];
    }
    const d = active?.value ?? 0;
    const lead = [`Dalam ${days} hari terakhir kamu mencatat ${fmt(total.value)} menit aktivitas di ${fmt(d)} hari.`, changeSentence(total, days, "menit")].filter(Boolean).join(" ");
    const out: Part[] = [text(lead), statPart(domain, days, total, `Aktivitas tercatat · ${days} hari`, `${fmt(d)} hari ada catatan`)];
    if (d < days) out.push(text("Ada hari yang mungkin belum dicatat. Mau cari aktivitas singkat yang muat di jadwalmu?"), suggestions([{ label: "Ya, 10 menit saja", message: "Ide olahraga ringan 10 menit" }]));
    out.push(trends);
    return out;
  }
  if (domain === "glucose") {
    const readings = byId(stats, "glucose.readings");
    const fasting = byId(stats, "glucose.fasting_median");
    if (!READY(readings) || readings.value === 0) return [text(`Belum ada pengukuran glukosa tercatat dalam ${days} hari terakhir.`), trends];
    const parts = [`Dalam ${days} hari terakhir ada ${fmt(readings.value)} pengukuran glukosa tercatat.`];
    if (READY(fasting)) parts.push(`Median glukosa puasa dari catatanmu ${fmt(fasting.value, glucoseUnit === "mg/dL" ? 0 : 1)} ${glucoseUnit}.`);
    else parts.push("Median glukosa puasa belum dihitung karena pengukuran puasanya belum cukup.");
    const shown = READY(fasting) ? fasting : readings;
    return [
      text(parts.join(" ")),
      statPart(domain, days, shown, READY(fasting) ? `Glukosa puasa · median ${days} hari` : `Pengukuran glukosa · ${days} hari`, `${fmt(readings.value)} pengukuran tercatat`),
      text("Angka ini ringkasan catatanmu, bukan penilaian medis. Bahas polanya dengan tenaga kesehatanmu bila perlu."),
      trends,
    ];
  }
  if (domain === "nutrition") {
    const logged = byId(stats, "nutrition.logged_days");
    const energy = byId(stats, "nutrition.calories_per_logged_day");
    const d = logged?.value ?? 0;
    if (d === 0) return [text(`Belum ada catatan makan dalam ${days} hari terakhir.`), { type: "link", label: "Catat makan", target: "LOG_MEAL" }];
    const parts = [`Kamu mencatat makan di ${fmt(d)} dari ${days} hari terakhir.`];
    if (READY(energy)) parts.push(`Rata-rata energi tercatat ${fmt(energy.value)} kkal pada hari yang ada catatannya.`);
    else parts.push("Rata-rata energi belum dihitung karena datanya belum cukup.");
    const shown = READY(energy) ? energy : logged!;
    return [text(parts.join(" ")), statPart(domain, days, shown, READY(energy) ? `Energi per hari tercatat · ${days} hari` : `Hari dengan catatan makan · ${days} hari`, `${fmt(d)} hari ada catatan`), trends];
  }
  if (domain === "medication") {
    const med = byId(stats, "medication.confirmed");
    const det = med?.detail ?? null;
    if (!med || !det || !det.scheduled) return [text("Belum ada jadwal obat aktif di catatanmu.")];
    const lead = `Dari ${fmt(det.scheduled)} jadwal obat dalam ${days} hari terakhir, ${fmt(det.taken ?? 0)} dicatat diminum dan ${fmt(det.skipped ?? 0)} dilewati.`;
    const rest = (det.unconfirmed ?? 0) > 0 ? ` ${fmt(det.unconfirmed!)} belum dikonfirmasi, dan itu belum tentu terlewat.` : "";
    return [text(lead + rest), statPart(domain, days, med, `Jadwal obat dikonfirmasi · ${days} hari`, `dari ${fmt(det.scheduled)} jadwal`)];
  }
  const rec = byId(stats, "logging.recorded_days");
  const d = rec?.value ?? 0;
  if (!rec || d === 0) return [text(`Belum ada catatan dalam ${days} hari terakhir. Mulai dari satu catatan kecil hari ini.`), { type: "link", label: "Buka Catatan", target: "LOG" }];
  return [text(`Kamu punya catatan di ${fmt(d)} dari ${days} hari terakhir.`), statPart("logging", days, rec, `Hari dengan catatan · ${days} hari`, `dari ${days} hari`), trends];
}

export const GREETING_REPLY: Part[] = [
  text("Halo! Aku bisa bantu melihat ringkasan catatanmu, mencari info makanan, atau memberi ide aktivitas. Mau mulai dari mana?"),
  suggestions(STARTERS),
];

export const THANKS_REPLY: Part[] = [text("Sama-sama. Aku di sini kalau kamu butuh lagi.")];

export const SUPPORT_REPLY: Part[] = [
  text("Wajar kalau naik turun. Konsisten tidak harus sempurna. Coba pilih satu langkah kecil yang paling mudah hari ini, misalnya mencatat satu kali makan atau jalan kaki 10 menit."),
  suggestions([
    { label: "Ide aktivitas 10 menit", message: "Ide olahraga ringan 10 menit" },
    { label: "Lihat catatanku minggu ini", message: "Bagaimana catatanku minggu ini?" },
  ]),
];

export const HELP_REPLY: Part[] = [
  text("Aku bisa bantu tiga hal: melihat ringkasan catatanmu, mencari info makanan dari tabel komposisi pangan, dan memberi ide aktivitas dari kebiasaanmu. Saran apa pun baru tersimpan setelah kamu setujui."),
  suggestions(STARTERS),
];

export const UNKNOWN_REPLY: Part[] = [
  text("Aku belum paham maksudmu. Coba tanyakan salah satu dari ini:"),
  suggestions(STARTERS),
];

export const NO_CONTEXT_REPLY: Part[] = [
  text("Belum ada saran sebelumnya di percakapan ini. Tulis yang ingin kamu cari, misalnya \"cari info tempe\" atau \"ide olahraga 15 menit\"."),
];

export const CLARIFY_FOOD_REPLY: Part[] = [text("Makanan apa yang ingin kamu cari? Tulis namanya, misalnya \"nasi goreng\" atau \"tempe\".")];

export function safetyReply(code: string, message: string, urgent: boolean): Part[] {
  const title = urgent ? "Segera cari bantuan" : ["MEDICATION_ADVICE", "INJURY_OR_PAIN", "DIAGNOSIS_REQUEST", "SYMPTOM_REVIEW"].includes(code) ? "Perlu tenaga kesehatan" : "Di luar yang bisa kubantu";
  return [{ type: "safety", code, title, text: message, urgent }];
}

export function consentReply(purpose: string): Part[] {
  const label: Record<string, string> = {
    personalized_ai: "Saran personal dari asisten beOkay",
    descriptive_summaries: "Membuat ringkasan dan insight deskriptif",
    health_data_processing: "Mencatat data kesehatan yang kamu masukkan",
    community_membership: "Bergabung dengan komunitas memakai alias",
  };
  return [{ type: "consent_required", purpose, text: `Untuk ini, aktifkan "${label[purpose] ?? purpose}" di Persetujuan data.` }];
}
