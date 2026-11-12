export type MemoryKind = "ACTIVITY_TIME" | "SCHEDULE" | "ACTIVITY_LIKE" | "ACTIVITY_DISLIKE" | "AVAILABLE_MINUTES" | "FOOD_CONTEXT" | "BARRIER" | "HEALTH_EVENT";
export type MemoryCandidate = { kind: MemoryKind; key: string; content: string };

export const MEMORY_TTL_DAYS: Partial<Record<MemoryKind, number>> = { FOOD_CONTEXT: 180, BARRIER: 60, HEALTH_EVENT: 7 };

export function ttlDaysFor(kind: string, key: string): number | null {
  if (kind === "HEALTH_EVENT") return key === "HEALTH_EVENT:FASTING_RAMADAN" ? 30 : key === "HEALTH_EVENT:FASTING" ? 14 : 7;
  return MEMORY_TTL_DAYS[kind as MemoryKind] ?? null;
}

const COOKS: Record<string, string> = { ibu: "ibu", mama: "ibu", ibuku: "ibu", istri: "istri", istriku: "istri", suami: "suami", suamiku: "suami", mertua: "mertua", anak: "anak", anakku: "anak", "aku sendiri": "aku sendiri", "saya sendiri": "aku sendiri", sendiri: "aku sendiri" };
const COOK = /(?:yang )?(?:masak|masakin|memasak)(?: di rumah)?(?: itu| biasanya| selalu)?\s+(ibu|mama|ibuku|istri|istriku|suami|suamiku|mertua|anak|anakku|aku sendiri|saya sendiri|sendiri)\b|\b(ibu|mama|istri|istriku|suami|suamiku|mertua)\s+(?:yang\s+)?(?:masak|memasak|masakin)\b/;
const EAT_OUT = /(?:sering|biasanya|tiap hari|setiap hari|hampir selalu)\s+(?:makan\s+)?(?:di luar|di warung|di kantin|beli makan|beli di luar|jajan|katering|pesan online|gofood|grabfood)/;
const PACKED = /(?:bawa|membawa)\s+bekal|bekal dari rumah/;
const FORGOT = /(?:sering|suka|gampang|selalu)\s+lupa(?:\s+(?:nyatet|mencatat|catat|nyatat|ngecek|cek))?/;
const NO_TIME = /(?:nggak|tidak|ga|gak|enggak)\s+(?:ada|punya)\s+waktu|waktunya\s+(?:nggak|tidak|ga|gak)\s+ada|sibuk banget|sibuk sekali/;
const TIRED = /(?:capek|lelah|kecapekan|kelelahan)\s+(?:pulang\s+)?(?:kerja|kerjaan|ngantor)/;
const FASTING_RAMADAN = /(?:lagi|sedang|sedang menjalani|bulan)\s+puasa\s+(?:ramadan|ramadhan)|puasa\s+(?:ramadan|ramadhan)/;
const FASTING = /(?:lagi|sedang|sedang menjalani)\s+puasa|puasa\s+(?:senin kamis|sunnah|daud)/;
const UNWELL = /(?:lagi|sedang)\s+(?:flu|pilek|batuk|kurang enak badan|tidak enak badan|nggak enak badan|gak enak badan|meriang|sakit)\b/;
const TRAVEL = /(?:lagi|sedang)\s+(?:mudik|perjalanan|bepergian|dinas luar kota|liburan)/;
const HEALTH_SENSITIVE = /(obat|insulin|metformin|diagnos|depresi|cemas|hamil|seks|bunuh|mati|kanker|stroke|jantung|operasi|luka)/;

export function extractContextCandidates(text: string): MemoryCandidate[] {
  const t = norm(text);
  const out: MemoryCandidate[] = [];
  if (t.length < 6) return out;
  const cook = t.match(COOK);
  if (cook) {
    const who = COOKS[cook[1] ?? cook[2] ?? ""] ?? null;
    if (who) out.push({ kind: "FOOD_CONTEXT", key: "FOOD_CONTEXT:COOK", content: who === "aku sendiri" ? "Biasanya memasak sendiri" : `Biasanya ${who} yang memasak di rumah` });
  }
  if (EAT_OUT.test(t)) out.push({ kind: "FOOD_CONTEXT", key: "FOOD_CONTEXT:EAT_OUT", content: "Sering makan di luar rumah" });
  if (PACKED.test(t)) out.push({ kind: "FOOD_CONTEXT", key: "FOOD_CONTEXT:PACKED", content: "Biasanya membawa bekal dari rumah" });
  if (FORGOT.test(t)) out.push({ kind: "BARRIER", key: "BARRIER:FORGOT", content: "Sering lupa mencatat" });
  if (NO_TIME.test(t)) out.push({ kind: "BARRIER", key: "BARRIER:TIME", content: "Sering tidak punya waktu" });
  if (TIRED.test(t)) out.push({ kind: "BARRIER", key: "BARRIER:ENERGY", content: "Sering kelelahan setelah bekerja" });
  if (!HEALTH_SENSITIVE.test(t)) {
    if (FASTING_RAMADAN.test(t)) out.push({ kind: "HEALTH_EVENT", key: "HEALTH_EVENT:FASTING_RAMADAN", content: "Sedang puasa Ramadan" });
    else if (FASTING.test(t)) out.push({ kind: "HEALTH_EVENT", key: "HEALTH_EVENT:FASTING", content: "Sedang berpuasa" });
    if (UNWELL.test(t)) out.push({ kind: "HEALTH_EVENT", key: "HEALTH_EVENT:UNWELL", content: "Sedang kurang sehat" });
    if (TRAVEL.test(t)) out.push({ kind: "HEALTH_EVENT", key: "HEALTH_EVENT:TRAVEL", content: "Sedang bepergian" });
  }
  return out;
}

export function keyForLlmMemory(kind: "FOOD_CONTEXT" | "BARRIER" | "HEALTH_EVENT", content: string): string {
  const slug = content
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "")
    .slice(0, 60);
  return `${kind}:LLM:${slug || "lainnya"}`;
}

const norm = (s: string) =>
  s
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const SENSITIVE = /(obat|insulin|metformin|gula darah|glukosa|diagnos|depresi|cemas|anxiety|hamil|haid|menstruasi|seks|agama|utang|hutang|gaji|penyakit|sakit|nyeri|luka|operasi|bunuh|mati)/;

export const ACTIVITIES: { pattern: string; label: string; type: string }[] = [
  { pattern: "jalan kaki|jalan pagi|jalan sore|jalan santai", label: "jalan kaki", type: "walking" },
  { pattern: "bersepeda|sepedaan|sepeda|gowes", label: "bersepeda", type: "cycling" },
  { pattern: "lari|jogging|joging", label: "lari", type: "running" },
  { pattern: "angkat beban|latihan beban|gym|fitness", label: "latihan beban", type: "strength" },
  { pattern: "berenang|renang", label: "berenang", type: "other" },
  { pattern: "yoga", label: "yoga", type: "other" },
  { pattern: "senam", label: "senam", type: "other" },
  { pattern: "bulu tangkis|badminton", label: "bulu tangkis", type: "other" },
];

const TIME = /(?:lebih suka|lebih enak|lebih nyaman|biasanya|enaknya|cuma bisa|hanya bisa|sempatnya|bisanya|maunya)\s+(?:(?:olahraga|jalan|aktivitas|beraktivitas|gerak|latihan)\s+)?(?:di\s+|pas\s+|waktu\s+)?(pagi|siang|sore|malam)\b/;
const BUSY = /(?:sibuk|nggak sempat|tidak sempat|ga sempat|gak sempat|repot)\s+(?:di\s+|kalau\s+|tiap\s+|setiap\s+|pas\s+|waktu\s+)?(pagi|siang|sore|malam|hari kerja|akhir pekan|weekend)\b/;
const MINUTES = /(?:cuma|hanya|paling)\s+(?:bisa|sempat|punya waktu|ada waktu)\s+(?:sekitar\s+)?(\d{1,3})\s*menit/;

export function extractMemoryCandidates(text: string): MemoryCandidate[] {
  const t = norm(text);
  const context = extractContextCandidates(text);
  if (t.length < 6 || SENSITIVE.test(t)) return context;
  const out: MemoryCandidate[] = [...context];
  const time = t.match(TIME);
  if (time) out.push({ kind: "ACTIVITY_TIME", key: "ACTIVITY_TIME", content: `Lebih suka beraktivitas ${time[1]} hari` });
  const busy = t.match(BUSY);
  if (busy) {
    const when = busy[1] === "weekend" ? "akhir pekan" : busy[1]!;
    const suffix = ["pagi", "siang", "sore", "malam"].includes(when) ? " hari" : "";
    out.push({ kind: "SCHEDULE", key: `SCHEDULE:${when}`, content: `Sering sibuk di ${when}${suffix}` });
  }
  const minutes = t.match(MINUTES);
  if (minutes) {
    const n = Number(minutes[1]);
    if (n >= 5 && n <= 180) out.push({ kind: "AVAILABLE_MINUTES", key: "AVAILABLE_MINUTES", content: `Punya waktu sekitar ${n} menit untuk aktivitas` });
  }
  for (const a of ACTIVITIES) {
    const dislike = new RegExp(`\\b(?:nggak|tidak|ga|gak|kurang|ndak|enggak)\\s+(?:terlalu\\s+)?(?:suka|senang|kuat)\\s+(?:${a.pattern})\\b`);
    const like = new RegExp(`(?<!(?:nggak|tidak|ga|gak|kurang|ndak|enggak)\\s(?:terlalu\\s)?)\\b(?:suka|senang|hobi|hobinya)\\s+(?:${a.pattern})\\b`);
    if (dislike.test(t)) out.push({ kind: "ACTIVITY_DISLIKE", key: `ACTIVITY_DISLIKE:${a.type}:${a.label}`, content: `Kurang suka ${a.label}` });
    else if (like.test(t)) out.push({ kind: "ACTIVITY_LIKE", key: `ACTIVITY_LIKE:${a.type}:${a.label}`, content: `Suka ${a.label}` });
  }
  const seen = new Set<string>();
  return out.filter((c) => (seen.has(c.key) ? false : (seen.add(c.key), true)));
}

export const MEMORY_KIND_LABELS: Record<MemoryKind, string> = {
  ACTIVITY_TIME: "Waktu aktivitas",
  SCHEDULE: "Jadwal",
  ACTIVITY_LIKE: "Aktivitas yang disukai",
  ACTIVITY_DISLIKE: "Aktivitas yang kurang disukai",
  AVAILABLE_MINUTES: "Waktu luang",
  FOOD_CONTEXT: "Konteks makan",
  BARRIER: "Hambatan",
  HEALTH_EVENT: "Kondisi sementara",
};

export const isUnwell = (memories: { kind: string; key: string }[]) => memories.some((m) => m.kind === "HEALTH_EVENT" && m.key === "HEALTH_EVENT:UNWELL");

export function activityConstraintsFrom(memories: { kind: string; key: string; content: string }[]) {
  const avoidTypes = memories.filter((m) => m.kind === "ACTIVITY_DISLIKE").map((m) => m.key.split(":")[1]!).filter((t) => t && t !== "other");
  const minutes = memories.find((m) => m.kind === "AVAILABLE_MINUTES")?.content.match(/(\d{1,3})\s*menit/);
  let maxMinutes = minutes ? Number(minutes[1]) : undefined;
  if (isUnwell(memories)) maxMinutes = Math.min(maxMinutes ?? 10, 10);
  return { avoidTypes: [...new Set(avoidTypes)], ...(maxMinutes && maxMinutes >= 5 ? { maxMinutes } : {}) };
}
