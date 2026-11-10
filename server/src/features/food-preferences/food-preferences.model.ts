/**
 * Pencocokan preferensi/alergi terhadap NAMA makanan. Ini heuristik berbasis nama, bukan daftar bahan:
 * tidak ada hasil yang berarti "aman". Bila tidak ada kecocokan, status tetap "NO_MATCH_FOUND" dengan
 * keterangan bahwa bahan lengkap tidak diketahui. Alergi tidak pernah dianggap terselesaikan oleh aplikasi.
 */
export type PreferenceKind = "allergy" | "restriction" | "dislike" | "preference";
export type Severity = "strict" | "soft";

export type PreferenceLike = { id: string; kind: PreferenceKind; term: string; label: string; severity: Severity };

export type Match = {
  preferenceId: string;
  kind: PreferenceKind;
  label: string;
  severity: Severity;
  /** NAME: kata kunci ada pada nama. COMMON_INGREDIENT: hidangan yang lazim memakai bahan itu (dugaan). */
  basis: "NAME" | "COMMON_INGREDIENT";
  evidence: string;
};

export type PreferenceCheck = {
  status: "EXCLUDED" | "WARNING" | "NO_MATCH_FOUND";
  matches: Match[];
  note: string;
};

export function normalizeTerm(input: string): string {
  return input
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

type Rule = { direct: string[]; common?: string[] };

/** Kata kunci per istilah baku. Kata ≤3 huruf dicocokkan sebagai kata utuh. */
const RULES: Record<string, Rule> = {
  kacang: {
    direct: ["kacang", "peanut", "bumbu kacang"],
    common: ["gado-gado", "gado gado", "pecel", "karedok", "ketoprak", "sate", "satay", "siomay", "batagor", "rujak", "lotek", "tahu gimbal", "asinan"],
  },
  udang: {
    direct: ["udang", "rebon", "terasi", "belacan", "shrimp", "prawn"],
    common: ["tom yum", "laksa", "bakwan udang"],
  },
  ikan: {
    direct: ["ikan", "tuna", "tongkol", "salmon", "bandeng", "lele", "gurame", "nila", "teri", "patin", "kakap", "mujair", "cakalang", "sarden", "pindang", "bilis", "dori"],
    common: ["pempek", "empek", "otak-otak", "otak otak", "siomay", "batagor", "somay"],
  },
  seafood: {
    direct: ["udang", "kerang", "cumi", "sotong", "tiram", "kepiting", "rajungan", "lobster", "ikan", "rebon", "terasi"],
    common: ["tom yum", "laksa", "paella"],
  },
  telur: {
    direct: ["telur", "egg", "omelet", "dadar", "ceplok", "mayones", "mayonnaise"],
    common: ["martabak", "bolu", "kue", "pancake", "pempek", "kwetiau goreng"],
  },
  susu: {
    direct: ["susu", "milk", "keju", "cheese", "yogurt", "yoghurt", "mentega", "butter", "krim", "cream", "whey", "kefir"],
    common: ["es krim", "ice cream", "latte", "cappuccino", "puding", "pudding", "martabak manis", "bolu", "kue"],
  },
  gluten: {
    direct: ["gandum", "terigu", "wheat", "roti", "mie", "mi", "bihun terigu", "pasta", "bread", "gluten", "spaghetti", "makaroni"],
    common: ["bakso", "siomay", "batagor", "martabak", "gorengan", "bakwan", "pizza", "burger", "pangsit", "kue", "donat", "cireng"],
  },
  kedelai: {
    direct: ["kedelai", "soy", "tahu", "tempe", "tempeh", "kecap", "tauco", "oncom"],
    common: ["gado-gado", "gado gado", "pecel", "ketoprak", "karedok", "pepes tahu"],
  },
  wijen: { direct: ["wijen", "sesame"], common: ["onde-onde", "onde onde"] },
  babi: { direct: ["babi", "pork", "bacon", "ham", "lard", "bak", "samcan", "ba kut"], common: ["sosis", "bakpao", "bakpau", "char siu", "siomay babi"] },
  alkohol: { direct: ["arak", "bir", "beer", "wine", "tuak", "rum", "brandy", "sake", "vodka", "whisky", "tape ketan"], common: ["tapai", "tape"] },
  daging: {
    direct: ["ayam", "sapi", "daging", "kambing", "bebek", "babi", "rendang", "sate", "bakso", "sosis", "burger", "dendeng", "abon", "iga", "lidah", "hati", "empal", "ikan", "udang", "cumi"],
    common: ["soto", "rawon", "gulai", "kari", "nasi goreng", "mie goreng", "mi goreng", "nasi padang", "pizza", "bubur ayam"],
  },
  hewani: {
    direct: ["ayam", "sapi", "daging", "kambing", "bebek", "babi", "ikan", "udang", "telur", "susu", "keju", "madu", "mentega", "rendang", "sate", "bakso", "sosis", "yogurt", "yoghurt"],
    common: ["soto", "rawon", "gulai", "kari", "nasi goreng", "mie goreng", "mi goreng", "nasi padang", "pizza", "martabak", "kue", "bolu"],
  },
};

/** Pembatasan gaya makan → kelompok istilah yang dikecualikan. */
export const RESTRICTION_PRESETS: Record<string, { label: string; excludes: string[] }> = {
  vegetarian: { label: "Vegetarian", excludes: ["daging"] },
  vegan: { label: "Vegan", excludes: ["hewani"] },
  "bebas babi": { label: "Bebas babi", excludes: ["babi"] },
  halal: { label: "Halal", excludes: ["babi", "alkohol"] },
};

/** Sinonim istilah yang diketik pengguna → istilah baku. */
const ALIASES: Record<string, string> = {
  "kacang tanah": "kacang", peanut: "kacang", kacangkacangan: "kacang",
  shrimp: "udang", prawn: "udang",
  fish: "ikan", egg: "telur", milk: "susu", dairy: "susu", laktosa: "susu", lactose: "susu",
  wheat: "gluten", terigu: "gluten", gandum: "gluten",
  soy: "kedelai", kedele: "kedelai", soya: "kedelai",
  sesame: "wijen", pork: "babi", alcohol: "alkohol", meat: "daging",
  "tanpa babi": "bebas babi", "no pork": "bebas babi",
};

export function canonicalTerm(raw: string): string {
  const t = normalizeTerm(raw);
  return ALIASES[t] ?? t;
}

function containsKeyword(haystack: string, keyword: string): boolean {
  const k = normalizeTerm(keyword);
  if (k.length <= 3) return new RegExp(`(^|[^a-z0-9])${k}([^a-z0-9]|$)`).test(haystack);
  return haystack.includes(k);
}

function termKeywords(term: string): Rule {
  const rule = RULES[term];
  if (rule) return rule;
  const preset = RESTRICTION_PRESETS[term];
  if (preset) {
    const merged: Rule = { direct: [], common: [] };
    for (const t of preset.excludes) {
      merged.direct.push(...(RULES[t]?.direct ?? []));
      merged.common!.push(...(RULES[t]?.common ?? []));
    }
    return merged;
  }
  // Istilah bebas: hanya kecocokan kata pada nama.
  return { direct: [term] };
}

const NOTE_UNKNOWN =
  "Pengecekan hanya berdasarkan nama. Bahan lengkap tidak diketahui; baca label atau tanyakan penyajinya bila kamu punya alergi.";

export function checkFood(name: string, prefs: PreferenceLike[], brand?: string | null): PreferenceCheck {
  const haystack = normalizeTerm(`${name} ${brand ?? ""}`);
  const matches: Match[] = [];
  for (const p of prefs) {
    const rule = termKeywords(p.term);
    const direct = rule.direct.find((k) => containsKeyword(haystack, k));
    if (direct) {
      matches.push({ preferenceId: p.id, kind: p.kind, label: p.label, severity: p.severity, basis: "NAME", evidence: direct });
      continue;
    }
    const common = rule.common?.find((k) => containsKeyword(haystack, k));
    if (common) matches.push({ preferenceId: p.id, kind: p.kind, label: p.label, severity: p.severity, basis: "COMMON_INGREDIENT", evidence: common });
  }
  // Kendala keras (alergi/pembatasan) yang cocok, baik dari nama maupun dugaan bahan lazim, mengecualikan.
  const excluded = matches.some((m) => m.severity === "strict");
  const status = excluded ? "EXCLUDED" : matches.length ? "WARNING" : "NO_MATCH_FOUND";
  return {
    status,
    matches,
    note: excluded
      ? "Dikecualikan karena kendala yang kamu tetapkan. Ini dugaan dari nama; periksa bahan sebenarnya."
      : status === "WARNING"
        ? "Cocok dengan sesuatu yang kamu tidak suka."
        : prefs.some((p) => p.severity === "strict")
          ? NOTE_UNKNOWN
          : "Tidak ada kecocokan dengan preferensimu.",
  };
}
