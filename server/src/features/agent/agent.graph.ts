import { checkFood, normalizeTerm, type PreferenceLike } from "../food-preferences/food-preferences.model.ts";
import { SAFETY_POLICY_VERSION, explanationIsSafe, validateCandidate } from "./agent.safety.ts";
import { executeTool, type ToolContext } from "./agent.tools.ts";
import { PERSONALIZATION_RULES_VERSION, boostFor, penaltyFor, tokensOf, type Profile } from "./personalization.ts";

/**
 * Graf eksplisit (state machine) untuk NUTRITION_ALTERNATIVES. Node dijalankan berurutan; tiap transisi dicatat sebagai
 * peristiwa run. Tidak ada efek samping domain di graf: ia hanya MENGUSULKAN. Penulisan terjadi di keputusan pengguna.
 */
export type Candidate = {
  key: string;
  name: string;
  source: string;
  provenance: string;
  per100g: Record<string, number | null>;
  completeness: "COMPLETE" | "PARTIAL" | "NONE";
  origin: "TKPI" | "USER_CATALOG";
  evidence: Record<string, unknown>;
  retrievalScore: number;
  matchedBy: string[];
};

export type RankedCandidate = Candidate & { score: number; penalty: number; penaltyTerms: string[]; boost: number; boostTerms: string[] };

export type GraphOutcome = {
  events: { type: string; payload: Record<string, unknown> }[];
  offered: RankedCandidate[];
  excludedByConstraints: number;
  rejectedByValidation: number;
  coverage: { reference: string; userCatalog: string };
  profileVersion: number;
  preferencesConsidered: number;
};

const core = ["calories", "carbohydrates", "protein", "fat", "fiber"] as const;
const completenessOf = (p: Record<string, number | null>): Candidate["completeness"] => {
  const known = core.filter((k) => p[k] !== null && p[k] !== undefined).length;
  return known === 5 ? "COMPLETE" : known === 0 ? "NONE" : "PARTIAL";
};
const num = (v: unknown): number | null => (v === null || v === undefined ? null : typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v)) ? Number(v) : null);

export const MAX_OFFERED = 3;

export async function runNutritionGraph(ctx: ToolContext, query: string, excludeKeys: ReadonlySet<string> = new Set()): Promise<GraphOutcome> {
  const events: GraphOutcome["events"] = [];
  const step = (type: string, payload: Record<string, unknown> = {}) => events.push({ type, payload });

  // 1. Konteks yang diizinkan
  step("NODE_ENTER", { node: "gather_context" });
  const prefs = await executeTool<PreferenceLike[]>(ctx, "get_food_preferences", {});
  const profile = await executeTool<Profile>(ctx, "get_personalization", {});
  step("CONTEXT_READY", { preferences: prefs.length, profileVersion: profile.version });

  // 2. Kandidat dari sumber yang punya provenans
  step("NODE_ENTER", { node: "retrieve_candidates" });
  const [ref, mine] = await Promise.allSettled([
    executeTool<{ status: string; items: any[] }>(ctx, "search_food_reference", { query, limit: 8 }),
    executeTool<any[]>(ctx, "search_user_foods", { query, limit: 6 }),
  ]);
  const coverage = {
    reference: ref.status === "fulfilled" ? (ref.value.status === "OK" ? "OK" : ref.value.status) : "UNAVAILABLE",
    userCatalog: mine.status === "fulfilled" ? "OK" : "UNAVAILABLE",
  };
  const candidates: Candidate[] = [];
  if (ref.status === "fulfilled") {
    ref.value.items.forEach((r, i) => {
      const per100g = { calories: num(r.per100g?.calories), carbohydrates: num(r.per100g?.carbohydrates), protein: num(r.per100g?.protein), fat: num(r.per100g?.fat), fiber: num(r.per100g?.fiber) };
      candidates.push({
        key: `tkpi:${r.code}`,
        name: String(r.name),
        source: String(r.source),
        provenance: String(r.provenance),
        per100g,
        completeness: completenessOf(per100g),
        origin: "TKPI",
        evidence: { kind: "TKPI", code: r.code, page: r.page ?? null, chapter: r.chapter ?? null, sourceRef: r.sourceRef ?? null, label: r.provenance, verification: r.verification },
        retrievalScore: 1 / (i + 1) + ((r.matchedBy as string[] | undefined)?.length ?? 0) * 0.1,
        matchedBy: (r.matchedBy as string[]) ?? [],
      });
    });
  }
  if (mine.status === "fulfilled") {
    mine.value.forEach((f, i) => {
      const per100g = { calories: num(f.per100g?.calories), carbohydrates: num(f.per100g?.carbohydrates), protein: num(f.per100g?.protein), fat: num(f.per100g?.fat), fiber: num(f.per100g?.fiber) };
      candidates.push({
        key: `food:${f.id}`,
        name: String(f.name),
        source: String(f.source ?? "Katalog pengguna"),
        provenance: `${f.source ?? "Katalog"} (${f.status === "estimated" ? "estimasi" : "dilaporkan pengguna"})`,
        per100g,
        completeness: completenessOf(per100g),
        origin: "USER_CATALOG",
        evidence: { kind: "USER_FOOD", foodId: f.id, source: f.source ?? null, status: f.status ?? null },
        retrievalScore: 1 / (i + 1) + 0.15, // makanan yang sudah ada di katalog pengguna sedikit diutamakan (familier)
        matchedBy: ["catalog"],
      });
    });
  }
  step("CANDIDATES_RETRIEVED", { count: candidates.length, coverage });

  // 3. Validasi sumber/angka, lalu kendala keras (alergi/pembatasan) SEBELUM peringkat apa pun
  step("NODE_ENTER", { node: "validate_and_filter" });
  let rejectedByValidation = 0;
  let excludedByConstraints = 0;
  const seen = new Set<string>();
  const eligible: Candidate[] = [];
  for (const c of candidates) {
    if (excludeKeys.has(c.key)) continue; // sudah ditawarkan pada giliran sebelumnya dalam percakapan ini
    const v = validateCandidate(c);
    if (!v.ok) {
      rejectedByValidation++;
      continue;
    }
    const nk = normalizeTerm(c.name);
    if (seen.has(nk)) continue;
    seen.add(nk);
    if (checkFood(c.name, prefs).status === "EXCLUDED") {
      excludedByConstraints++;
      continue;
    }
    eligible.push(c);
  }
  step("FILTERED", { eligible: eligible.length, excludedByConstraints, rejectedByValidation });

  // 4. Peringkat deterministik: kecocokan + kelengkapan data + preferensi yang dipelajari. Skor tidak dapat memunculkan kembali yang sudah dikecualikan.
  step("NODE_ENTER", { node: "rank" });
  const bonus = { COMPLETE: 0.3, PARTIAL: 0.1, NONE: 0 } as const;
  const ranked: RankedCandidate[] = eligible
    .map((c) => {
      const p = penaltyFor(c.name, profile);
      const b = boostFor(c.name, profile);
      return { ...c, penalty: p.penalty, penaltyTerms: p.matched, boost: b.boost, boostTerms: b.matched, score: Math.round((c.retrievalScore + bonus[c.completeness] - p.penalty + b.boost) * 1000) / 1000 };
    })
    .sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
  const offered = ranked.slice(0, MAX_OFFERED);
  step("RANKED", { offered: offered.map((o) => ({ key: o.key, score: o.score, penalty: o.penalty })), rulesVersion: PERSONALIZATION_RULES_VERSION });
  return { events, offered, excludedByConstraints, rejectedByValidation, coverage, profileVersion: profile.version, preferencesConsidered: prefs.length };
}

export type RecommendationPayload = {
  title: string;
  explanation: string;
  candidate: { key: string; name: string; source: string; provenance: string; per100g: Record<string, number | null>; completeness: string; origin: string };
  evidenceRefs: Record<string, unknown>[];
  limitations: string[];
  dataCoverage: string;
  policyVersion: string;
  rankingReason: string;
  personalization: { profileVersion: number; rulesVersion: string; penalty: number; matchedTerms: string[]; boost?: number; boostedTerms?: string[] };
  query: string;
  requiresConfirmation: true;
  strictConstraintsActive: boolean;
};

/** Teks dibuat dari templat (bukan model) dan tetap melewati gerbang klaim terlarang. */
export function buildRecommendation(c: RankedCandidate, o: GraphOutcome, query: string, strictConstraintsActive: boolean): RecommendationPayload {
  const reasons: string[] = [`cocok dengan pencarianmu "${query}"`];
  if (c.completeness === "COMPLETE") reasons.push("data gizinya lengkap");
  if (c.origin === "USER_CATALOG") reasons.push("sudah ada di daftar makananmu");
  if (c.boostTerms.length) reasons.push(`peringkatnya dinaikkan karena catatan makanmu menunjukkan kamu pernah memakan pilihan dengan kata: ${c.boostTerms.join(", ")}`);
  if (c.penaltyTerms.length) reasons.push(`peringkatnya diturunkan karena kamu pernah menolak pilihan dengan kata: ${c.penaltyTerms.join(", ")}`);
  const limitations = [
    "Alergi hanya dicek dari nama makanan, bukan bahan lengkapnya.",
    "Porsimu belum diketahui, jadi total gizi belum dihitung.",
    "Ini pilihan untuk kamu pertimbangkan, bukan perintah dan bukan saran medis.",
  ];
  if (c.origin === "TKPI") limitations.push("Angka dibaca otomatis dari tabel dan belum diperiksa oleh manusia.");
  if (c.completeness !== "COMPLETE") limitations.push("Sebagian nilai gizi belum ada dan sengaja dikosongkan, bukan ditebak.");
  const explanation = `Pertimbangkan ${c.name}: ${reasons.join("; ")}. Gizi per 100 gram dari ${c.provenance}.`;
  if (!explanationIsSafe(explanation)) throw new Error("EXPLANATION_REJECTED_BY_SAFETY_GATE");
  return {
    title: `Pertimbangkan: ${c.name}`,
    explanation,
    candidate: { key: c.key, name: c.name, source: c.source, provenance: c.provenance, per100g: c.per100g, completeness: c.completeness, origin: c.origin },
    evidenceRefs: [c.evidence],
    limitations,
    dataCoverage: c.completeness,
    policyVersion: SAFETY_POLICY_VERSION,
    rankingReason: "Diurutkan dari yang paling cocok dengan pencarianmu, datanya paling lengkap, dan sesuai pilihanmu.",
    personalization: { profileVersion: o.profileVersion, rulesVersion: PERSONALIZATION_RULES_VERSION, penalty: c.penalty, matchedTerms: c.penaltyTerms, boost: c.boost, boostedTerms: c.boostTerms },
    query,
    requiresConfirmation: true,
    strictConstraintsActive,
  };
}

export const queryTermsOf = (query: string) => tokensOf(query);
