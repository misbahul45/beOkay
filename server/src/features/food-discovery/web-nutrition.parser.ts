export type WebPer100g = { calories: number | null; carbohydrates: number | null; protein: number | null; fat: number | null; fiber: number | null };

const NUM = String.raw`(\d{1,4}(?:[.,]\d{1,3})?)`;
const SEP = String.raw`\s*(?:\*\*)?\s*(?:[:|=]|\s)\s*(?:\*\*)?\s*`;
const PATTERNS: Record<keyof WebPer100g, RegExp> = {
  calories: new RegExp(String.raw`\b(?:energi|kalori|energy|calories)\b(?:\s*\([^)]{0,12}\))?${SEP}${NUM}\s*(?:kkal|kcal|kal|cal)\b`),
  protein: new RegExp(String.raw`\b(?:protein|prot)\b(?:\s*\([^)]{0,12}\))?${SEP}${NUM}\s*(?:g|gr|gram)\b`),
  fat: new RegExp(String.raw`\b(?:lemak total|lemak|total fat|fat)\b(?:\s*\([^)]{0,12}\))?${SEP}${NUM}\s*(?:g|gr|gram)\b`),
  carbohydrates: new RegExp(String.raw`\b(?:karbohidrat total|karbohidrat|karbo|karb|carbohydrates?|total carbohydrate|carbs?)\b(?:\s*\([^)]{0,12}\))?${SEP}${NUM}\s*(?:g|gr|gram)\b`),
  fiber: new RegExp(String.raw`\b(?:serat pangan|serat|dietary fiber|fiber|fibre)\b(?:\s*\([^)]{0,12}\))?${SEP}${NUM}\s*(?:g|gr|gram)\b`),
};
const BASIS = /(per|tiap|setiap|dalam|untuk)\s*100\s*(?:g|gr|gram)\b|(takaran saji|ukuran porsi|serving size)\s*[:|]?\s*100\s*(?:g|gr|gram)\b|(per sajian|per saji|per porsi)[^0-9a-z]{0,24}\(?\s*100\s*(?:g|gr|gram)\b|\b100\s*(?:g|gr|gram)\s*(?:bdd|bagian yang dapat dimakan)/;
const ENERGY_100G = /\b100\s*(?:g|gr|gram)\s*[-–:]\s*(\d{1,4}(?:[.,]\d{1,2})?)\s*(?:kkal|kcal|kal)\b/;
const LIMITS: WebPer100g = { calories: 950, carbohydrates: 100, protein: 100, fat: 100, fiber: 100 };
const KEYS = Object.keys(PATTERNS) as (keyof WebPer100g)[];

const toNumber = (raw: string) => Number(raw.replace(/\.(?=\d{3}\b)/, "").replace(",", "."));
const round = (v: number) => Math.round(v * 100) / 100;

function extract(window: string): WebPer100g {
  const out: WebPer100g = { calories: null, carbohydrates: null, protein: null, fat: null, fiber: null };
  for (const key of KEYS) {
    const m = window.match(PATTERNS[key]);
    if (!m) continue;
    const v = toNumber(m[1]!);
    if (Number.isFinite(v) && v >= 0) out[key] = v;
  }
  return out;
}

function plausible(out: WebPer100g): WebPer100g | null {
  for (const key of KEYS) {
    const v = out[key];
    if (v !== null && (!Number.isFinite(v) || v < 0 || v > LIMITS[key]!)) return null;
  }
  const macros = [out.carbohydrates, out.protein, out.fat].filter((v) => v !== null).length;
  if (out.calories === null || macros < 2) return null;
  if (out.carbohydrates !== null && out.protein !== null && out.fat !== null) {
    const computed = 4 * out.carbohydrates + 4 * out.protein + 9 * out.fat;
    if (Math.abs(computed - out.calories) / Math.max(out.calories, 1) > 0.35) return null;
  }
  if ((out.carbohydrates ?? 0) + (out.protein ?? 0) + (out.fat ?? 0) + (out.fiber ?? 0) > 100) return null;
  return Object.fromEntries(KEYS.map((k) => [k, out[k] === null ? null : round(out[k]!)])) as WebPer100g;
}

const SERVING_LINE = /\bper\s+([^-–:\n]{1,40}?)\s*[-–:]\s*(?=kalori|energi)/g;

function scaledFromServing(text: string): WebPer100g | null {
  let tries = 0;
  for (const m of text.matchAll(SERVING_LINE)) {
    if (++tries > 6 || m.index === undefined) break;
    const raw = extract(text.slice(m.index, m.index + 260));
    if (raw.calories === null || raw.calories <= 0) continue;
    const stated = text.slice(m.index, m.index + 700).match(ENERGY_100G);
    const grams = m[1]!.match(/(\d{1,4}(?:[.,]\d{1,2})?)\s*(?:g|gr|gram)\b/);
    const per100 = stated ? toNumber(stated[1]!) : null;
    let factor: number | null = null;
    if (grams) {
      const g = toNumber(grams[1]!);
      if (!Number.isFinite(g) || g < 5 || g > 1000) continue;
      factor = 100 / g;
      if (per100 === null || Math.abs(raw.calories * factor - per100) / per100 > 0.15) continue;
    } else if (per100 !== null && per100 > 0) {
      factor = per100 / raw.calories;
    }
    if (factor === null) continue;
    const scaled = Object.fromEntries(KEYS.map((k) => [k, raw[k] === null ? null : raw[k]! * factor!])) as WebPer100g;
    if (per100 !== null) scaled.calories = per100;
    const ok = plausible(scaled);
    if (ok) return ok;
  }
  return null;
}

function parseWindow(text: string): WebPer100g | null {
  const scaled = scaledFromServing(text);
  if (scaled) return scaled;
  const basis = text.match(BASIS);
  if (basis && basis.index !== undefined) return plausible(extract(text.slice(Math.max(0, basis.index - 300), basis.index + 3000)));
  return null;
}

const ENTRY_END = /\|\s*\|\s*\[|\n#{1,6}\s/;

export function parseNutritionPer100g(markdown: string, anchor?: string): WebPer100g | null {
  const text = markdown.slice(0, 60_000).toLowerCase().replace(/&nbsp;/g, " ").replace(/[ \t]+/g, " ");
  const term = anchor?.toLowerCase().trim();
  if (!term) return parseWindow(text);
  let from = 0;
  for (let i = 0; i < 8; i++) {
    const at = text.indexOf(term, from);
    if (at < 0) break;
    const rest = text.slice(at, at + 1500);
    const cut = rest.slice(20).search(ENTRY_END);
    const window = cut >= 0 ? rest.slice(0, cut + 20) : rest;
    const found = parseWindow(window);
    if (found) return found;
    from = at + term.length;
  }
  return null;
}

const TITLE_PREFIX = /^(?:kalori dan informasi gizi|informasi gizi|nilai kandungan gizi|kandungan gizi|nilai gizi|fakta gizi|kalori)\s+/;

export function foodNameFromTitle(title: string): string {
  const base = title.split(/\s+[|–-]\s+/)[0]!.trim();
  const stripped = base.toLowerCase().replace(TITLE_PREFIX, "").trim();
  const name = stripped || base.toLowerCase();
  return name.charAt(0).toUpperCase() + name.slice(1, 80);
}
