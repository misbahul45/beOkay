export type MemoryKind = "ACTIVITY_TIME" | "SCHEDULE" | "ACTIVITY_LIKE" | "ACTIVITY_DISLIKE" | "AVAILABLE_MINUTES";
export type MemoryCandidate = { kind: MemoryKind; key: string; content: string };

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
  if (t.length < 6 || SENSITIVE.test(t)) return [];
  const out: MemoryCandidate[] = [];
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
};

export function activityConstraintsFrom(memories: { kind: string; key: string; content: string }[]) {
  const avoidTypes = memories.filter((m) => m.kind === "ACTIVITY_DISLIKE").map((m) => m.key.split(":")[1]!).filter((t) => t && t !== "other");
  const minutes = memories.find((m) => m.kind === "AVAILABLE_MINUTES")?.content.match(/(\d{1,3})\s*menit/);
  const maxMinutes = minutes ? Number(minutes[1]) : undefined;
  return { avoidTypes: [...new Set(avoidTypes)], ...(maxMinutes && maxMinutes >= 5 ? { maxMinutes } : {}) };
}
