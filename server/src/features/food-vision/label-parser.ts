import type { Per100g } from "../food-discovery/food-candidate.ts";

export type LabelBasis = "per_100g" | "per_serving" | "unknown";

export type LabelParse = {
  basis: LabelBasis;
  /** Takaran saji dalam gram bila tercetak; null bila tidak ada atau bukan gram. */
  servingGrams: number | null;
  /** Nilai apa adanya sesuai kolom yang dipakai (per 100 g atau per sajian). */
  printed: Per100g;
  /** Nilai per 100 g; null bila tidak bisa dihitung tanpa menebak. */
  per100g: Per100g;
  flags: string[];
};

const EMPTY: Per100g = { calories: null, carbohydrates: null, protein: null, fat: null, fiber: null };

type Nutrient = keyof Per100g;

const MATCHERS: { key: Nutrient; test: (l: string) => boolean; units: RegExp }[] = [
  {
    key: "calories",
    test: (l) => /\b(energi|energy|kalori|calories)\b/.test(l) && !/(dari lemak|from fat|lemak)/.test(l),
    units: /(\d+(?:\.\d+)?)\s*(kkal|kcal|cal|kj)\b/g,
  },
  {
    key: "fat",
    test: (l) => /\b(lemak|fat)\b/.test(l) && !/(jenuh|trans|saturated|tak jenuh|unsaturated|dari lemak|from fat)/.test(l),
    units: /(\d+(?:\.\d+)?)\s*(g|gr|gram|mg)\b/g,
  },
  {
    key: "carbohydrates",
    test: (l) => /\b(karbohidrat|carbohydrate|carbohydrates|carbs)\b/.test(l),
    units: /(\d+(?:\.\d+)?)\s*(g|gr|gram|mg)\b/g,
  },
  {
    key: "protein",
    test: (l) => /\bprotein\b/.test(l),
    units: /(\d+(?:\.\d+)?)\s*(g|gr|gram|mg)\b/g,
  },
  {
    key: "fiber",
    test: (l) => /\b(serat|fiber|fibre)\b/.test(l),
    units: /(\d+(?:\.\d+)?)\s*(g|gr|gram|mg)\b/g,
  },
];

const clean = (text: string) =>
  text
    .toLowerCase()
    .replace(/[|*_`#>]/g, " ")
    .replace(/(\d),(\d)/g, "$1.$2")
    .replace(/[ \t]+/g, " ");

function readNumbers(line: string, units: RegExp): { value: number; unit: string }[] {
  const out: { value: number; unit: string }[] = [];
  for (const m of line.matchAll(new RegExp(units.source, "g"))) out.push({ value: Number(m[1]), unit: m[2]! });
  return out;
}

function toBase(key: Nutrient, value: number, unit: string, flags: string[]): number | null {
  if (key === "calories") {
    if (unit === "kj") {
      flags.push("energy_from_kj");
      return value / 4.184;
    }
    return value;
  }
  return unit === "mg" ? value / 1000 : value;
}

/**
 * Parser deterministik teks OCR label gizi (Indonesia/Inggris). Model OCR hanya membaca teks;
 * angka diambil di sini dengan aturan eksplisit. Yang tidak terbaca atau ambigu tetap null.
 */
export function parseLabel(markdown: string): LabelParse {
  const text = clean(markdown);
  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
  const flags: string[] = [];

  const servingMatch = text.match(/(takaran saji|ukuran saji|serving size|per sajian|per saji|per serving)[^0-9\n]{0,30}(\d+(?:\.\d+)?)\s*(g|gr|gram|ml)\b/);
  let servingGrams: number | null = null;
  if (servingMatch) {
    if (servingMatch[3] === "ml") flags.push("serving_in_ml");
    else servingGrams = Number(servingMatch[2]);
  }

  const per100Idx = text.search(/per\s*100\s*(g|gr|gram)\b/);
  const per100ml = /per\s*100\s*ml\b/.test(text);
  const servingIdx = text.search(/(per saji|per sajian|per serving|takaran saji|serving size|persaji)/);
  const hasPer100 = per100Idx >= 0;
  const hasServingCol = servingIdx >= 0;
  if (per100ml && !hasPer100) flags.push("basis_per_100ml");

  const printed: Per100g = { ...EMPTY };
  let twoColumns = false;
  for (const line of lines) {
    for (const m of MATCHERS) {
      if (printed[m.key] !== null || !m.test(line)) continue;
      const nums = readNumbers(line, m.units);
      if (nums.length === 0) continue;
      // Dua kolom (per 100 g dan per sajian): pilih kolom sesuai urutan judul.
      let pick = nums[0]!;
      if (nums.length >= 2 && hasPer100 && hasServingCol) {
        twoColumns = true;
        pick = per100Idx < servingIdx ? nums[0]! : nums[1]!;
      }
      printed[m.key] = toBase(m.key, pick.value, pick.unit, flags);
    }
  }

  const known = Object.values(printed).filter((v) => v !== null).length;
  if (known === 0) flags.push("no_nutrition_found");

  // Dasar nilai hanya ditetapkan bila tidak ambigu; selain itu "unknown" (nilai tercetak tetap dikembalikan).
  let basis: LabelBasis = "unknown";
  if (known > 0) {
    if (twoColumns || (hasPer100 && !hasServingCol)) basis = "per_100g";
    else if (!hasPer100 && (servingGrams !== null || hasServingCol)) basis = "per_serving";
  }
  if (known > 0 && basis === "unknown") flags.push("basis_unclear");

  let per100g: Per100g = { ...EMPTY };
  if (basis === "per_100g") per100g = { ...printed };
  else if (basis === "per_serving") {
    if (servingGrams && servingGrams > 0) {
      const f = 100 / servingGrams;
      for (const k of Object.keys(printed) as Nutrient[]) per100g[k] = printed[k] === null ? null : Math.round(printed[k]! * f * 10000) / 10000;
    } else flags.push("serving_size_unknown");
  }
  for (const k of Object.keys(per100g) as Nutrient[]) if (per100g[k] !== null) per100g[k] = Math.round(per100g[k]! * 10000) / 10000;

  return { basis, servingGrams, printed, per100g, flags: [...new Set(flags)] };
}
