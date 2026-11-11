const WHY_RE = /\b(kenapa|mengapa|alasan(nya)?|dasar(nya)?)\b/;
const MORE_RE = /\b(yang lain|lainnya|ada lagi|opsi lain|pilihan lain|selain (itu|ini)|coba lagi)\b/;
export function classifyFollowUp(message: string): "WHY" | "MORE" | null {
  const m = message.toLowerCase();
  if (WHY_RE.test(m)) return "WHY";
  return MORE_RE.test(m) ? "MORE" : null;
}

const STOP = new Set(["alternatif", "pengganti", "ganti", "untuk", "makanan", "makan", "apa", "yang", "dong", "tolong", "saya", "aku", "cari", "carikan", "dari", "dengan", "atau", "dan", "pilihan", "rekomendasi", "saran", "usul", "menu", "lauk", "bisa", "boleh", "ada", "sebagai", "buat", "mau", "ingin"]);

export function extractQuery(message: string): string | null {
  const tokens = message.toLowerCase().normalize("NFKD").replace(/\p{M}/gu, "").replace(/[^a-z0-9\s-]/g, " ").split(/\s+/).filter((t) => t.length >= 2 && !STOP.has(t));
  return tokens.length ? tokens.slice(0, 4).join(" ") : null;
}

const NUTRITION_INTENT = /(alternatif|pengganti|ganti|rekomendasi|saran|pilihan|usul|cari|makan|makanan|menu|lauk|snack|camilan|sarapan)/;
const ACTIVITY_INTENT = /(olahraga|aktivitas|jalan kaki|jogging|bersepeda|sepeda|latihan|bergerak|gerak badan|workout|exercise)/;
const FOOD_WORDS = /(makan|makanan|menu|lauk|snack|camilan|sarapan|minum)/;
export function classifyIntent(message: string, explicitQuery?: string): "NUTRITION_ALTERNATIVES" | "ACTIVITY_PLAN" | "UNSUPPORTED" {
  const m = message.toLowerCase();
  if (explicitQuery) return "NUTRITION_ALTERNATIVES";
  if (ACTIVITY_INTENT.test(m) && !FOOD_WORDS.test(m)) return "ACTIVITY_PLAN";
  return NUTRITION_INTENT.test(m) ? "NUTRITION_ALTERNATIVES" : "UNSUPPORTED";
}
