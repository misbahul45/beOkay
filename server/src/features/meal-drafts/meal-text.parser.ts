export type MealCategory = "breakfast" | "lunch" | "dinner" | "snack";
export type MealUnit = "g" | "ml" | "portion" | "piece";

export type ParsedItem = {
  text: string;
  name: string;
  quantity: number;
  unit: MealUnit;
  unitLabel: string | null;
  quantityStated: boolean;
  grams: number | null;
};

export type ParsedMeal = { category: MealCategory | null; items: ParsedItem[] };

const norm = (s: string) =>
  s
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9.,/+\s-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const CONSUMED = /\b(tadi|barusan|habis|sudah|udah|baru|baru saja|td)\s+((pagi|siang|sore|malam)\s+)?((aku|saya)\s+)?(makan|sarapan|minum|ngemil|nyemil)\b|\b(pagi|siang|sore|malam)\s+(tadi|ini)\s+((aku|saya)\s+)?(makan|sarapan|minum|ngemil)\b|\b(aku|saya|gue|gw)\s+(makan|sarapan|minum|ngemil)\b|^(sarapan|makan siang|makan malam|ngemil|nyemil)\s+(pakai|pake|dengan|nasi|roti|mie|bubur|\w+\s*(,|dan))|\bcatat(kan|in)?\s+(makan|makanan|sarapan|minum)/;
const QUESTION = /\?|\b(apa|apakah|berapa|gimana|bagaimana|boleh|sebaiknya|kenapa|mengapa|enak gak|aman gak|bisa gak)\b/;

export function isMealLogStatement(text: string): boolean {
  const t = norm(text);
  return CONSUMED.test(t) && !QUESTION.test(text.toLowerCase());
}

const CATEGORY: [MealCategory, RegExp][] = [
  ["breakfast", /\b(sarapan|tadi pagi|pagi tadi|pagi ini)\b/],
  ["lunch", /\b(makan siang|tadi siang|siang tadi|siang ini)\b/],
  ["dinner", /\b(makan malam|tadi malam|malam tadi|malam ini|semalam)\b/],
  ["snack", /\b(ngemil|nyemil|camilan|cemilan|snack|kudapan)\b/],
];

const LEAD = /^(tolong\s+)?(catat(kan|in)?\s+)?((aku|saya|gue|gw)\s+)?((tadi|barusan|habis|sudah|udah|baru saja|baru|td)\s+)?((pagi|siang|sore|malam)\s+((tadi|ini)\s+)?)?((aku|saya|gue|gw)\s+)?(sarapan|makan siang|makan malam|makan|minum|ngemil|nyemil)(an)?\s*(:|nya)?\s*/;
const SPLIT = /\s*(?:,|;|\+|\bdan\b|\bsama\b|\bserta\b|\bplus\b|\bpakai\b|\bpake\b|\bdengan\b|\bdi tambah\b|\bditambah\b)\s*/;
const FILLER = /\b(tadi|barusan|pagi|siang|sore|malam|ini|itu|aja|saja|juga|lagi|kok|sih|deh|ya|yang|enak|banget|dong)\b/g;

const NUMBER: Record<string, number> = {
  satu: 1, dua: 2, tiga: 3, empat: 4, lima: 5, enam: 6, tujuh: 7, delapan: 8, sembilan: 9, sepuluh: 10,
  setengah: 0.5, seperempat: 0.25, "1/2": 0.5, "1/4": 0.25,
};
const UNITS: Record<string, { unit: MealUnit; label: string }> = {
  piring: { unit: "portion", label: "piring" },
  mangkuk: { unit: "portion", label: "mangkuk" },
  mangkok: { unit: "portion", label: "mangkuk" },
  porsi: { unit: "portion", label: "porsi" },
  bungkus: { unit: "portion", label: "bungkus" },
  gelas: { unit: "portion", label: "gelas" },
  cangkir: { unit: "portion", label: "cangkir" },
  potong: { unit: "piece", label: "potong" },
  buah: { unit: "piece", label: "buah" },
  butir: { unit: "piece", label: "butir" },
  lembar: { unit: "piece", label: "lembar" },
  biji: { unit: "piece", label: "biji" },
  iris: { unit: "piece", label: "iris" },
  sendok: { unit: "piece", label: "sendok" },
  sdm: { unit: "piece", label: "sendok makan" },
  sdt: { unit: "piece", label: "sendok teh" },
  g: { unit: "g", label: "g" },
  gr: { unit: "g", label: "g" },
  gram: { unit: "g", label: "g" },
  ml: { unit: "ml", label: "ml" },
};
const UNIT_WORDS = Object.keys(UNITS).sort((a, b) => b.length - a.length).join("|");
const NUM_WORDS = Object.keys(NUMBER).map((k) => k.replace("/", "\\/")).join("|");
const QTY = new RegExp(`(?:^|\\s)(\\d+(?:[.,]\\d+)?|${NUM_WORDS})\\s*(${UNIT_WORDS})(?=\\s|$)`);
const SE_UNIT = new RegExp(`(?:^|\\s)se(${UNIT_WORDS.split("|").filter((u) => u.length > 2).join("|")})(?=\\s|$)`);
const BARE_NUM = /^(\d+(?:[.,]\d+)?|satu|dua|tiga|empat|lima)\s+(?=\S)/;

function parseQuantity(raw: string): { quantity: number; unit: MealUnit; unitLabel: string | null; stated: boolean; rest: string } {
  const q = raw.match(QTY);
  if (q) {
    const n = NUMBER[q[1]!] ?? Number(q[1]!.replace(",", "."));
    const u = UNITS[q[2]!]!;
    return { quantity: n, unit: u.unit, unitLabel: u.label, stated: true, rest: raw.replace(q[0], " ") };
  }
  const se = raw.match(SE_UNIT);
  if (se) {
    const u = UNITS[se[1]!]!;
    return { quantity: 1, unit: u.unit, unitLabel: u.label, stated: true, rest: raw.replace(se[0], " ") };
  }
  const bare = raw.match(BARE_NUM);
  if (bare) {
    const n = NUMBER[bare[1]!] ?? Number(bare[1]!.replace(",", "."));
    return { quantity: n, unit: "piece", unitLabel: null, stated: true, rest: raw.slice(bare[0].length) };
  }
  return { quantity: 1, unit: "portion", unitLabel: null, stated: false, rest: raw };
}

export function parseMealText(text: string): ParsedMeal {
  const t = norm(text);
  const category = CATEGORY.find(([, re]) => re.test(t))?.[0] ?? null;
  const body = t.replace(LEAD, "").replace(/\b(pagi|siang|sore|malam)\s+(tadi|ini)\b/g, " ");
  const items: ParsedItem[] = [];
  for (const chunk of body.split(SPLIT)) {
    const piece = chunk.trim();
    if (piece.length < 2) continue;
    const q = parseQuantity(piece);
    const name = q.rest.replace(FILLER, " ").replace(/[.,]/g, " ").replace(/\s+/g, " ").trim();
    if (name.length < 2 || /^\d+$/.test(name)) continue;
    if (!Number.isFinite(q.quantity) || q.quantity <= 0 || q.quantity > 10000) continue;
    items.push({
      text: piece,
      name: name.slice(0, 80),
      quantity: q.quantity,
      unit: q.unit,
      unitLabel: q.unitLabel,
      quantityStated: q.stated,
      grams: q.unit === "g" ? q.quantity : null,
    });
    if (items.length >= 10) break;
  }
  return { category, items };
}

export function sanitizePhotoName(name: string): string {
  return norm(name).replace(/[^a-z0-9\s-]/g, " ").replace(/\s+/g, " ").trim().slice(0, 60);
}
