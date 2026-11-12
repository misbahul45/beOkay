/** Fusi peringkat leksikal + semantik (Reciprocal Rank Fusion). Murni, tanpa I/O. */
export type Ranked = { id: string };

export function reciprocalRankFusion<T extends Ranked>(lists: { name: string; items: T[] }[], limit: number, k = 60) {
  const merged = new Map<string, { item: T; score: number; by: string[] }>();
  for (const list of lists) {
    list.items.forEach((item, rank) => {
      const cur = merged.get(item.id) ?? { item, score: 0, by: [] };
      cur.score += 1 / (k + rank + 1);
      cur.by.push(list.name);
      merged.set(item.id, cur);
    });
  }
  return [...merged.values()]
    .sort((a, b) => b.score - a.score || a.item.id.localeCompare(b.item.id))
    .slice(0, limit)
    .map((m) => ({ ...m.item, score: Math.round(m.score * 10_000) / 10_000, matchedBy: m.by }));
}

/** Label singkat untuk pengguna. Rincian (dibaca otomatis dari PDF, belum diperiksa manusia) ada di batasan saran dan catatan sumber. */
export const PROVENANCE_LABEL = "Tabel Komposisi Pangan Indonesia";
export const REFERENCE_SOURCE = "Tabel Komposisi Pangan Indonesia";
export const REFERENCE_VERSION = "TKPI 2017";

export const CURATED_PROVENANCE = "Kurasi beOkay · dari bahan TKPI";

export type ReferenceRow = {
  id: string; code: string; name: string; sourceRef: string | null; page: number | null; chapter: string | null;
  water: number | null; calories: number | null; protein: number | null; fat: number | null; carbohydrates: number | null; fiber: number | null; ash: number | null;
  status?: string; source?: string; sourceVersion?: string; method?: string | null;
  servingMinG?: number | null; servingTypicalG?: number | null; servingMaxG?: number | null;
};

export function toReferenceFood(r: ReferenceRow) {
  const core = [r.calories, r.carbohydrates, r.protein, r.fat, r.fiber];
  const known = core.filter((v) => v !== null).length;
  const curated = r.status === "curated";
  return {
    id: r.id,
    code: r.code,
    name: r.name,
    brand: null,
    source: curated ? r.source ?? REFERENCE_SOURCE : REFERENCE_SOURCE,
    sourceVersion: curated ? r.sourceVersion ?? REFERENCE_VERSION : REFERENCE_VERSION,
    sourceRef: r.sourceRef,
    provenance: curated ? CURATED_PROVENANCE : PROVENANCE_LABEL,
    verification: (curated ? "curated" : "verified_auto") as "curated" | "verified_auto",
    serving: curated && r.servingTypicalG ? { minGrams: r.servingMinG ?? null, typicalGrams: r.servingTypicalG, maxGrams: r.servingMaxG ?? null } : null,
    chapter: r.chapter,
    page: r.page,
    per100g: { calories: r.calories, carbohydrates: r.carbohydrates, protein: r.protein, fat: r.fat, fiber: r.fiber },
    water: r.water,
    ash: r.ash,
    completeness: known === 5 ? ("COMPLETE" as const) : known === 0 ? ("NONE" as const) : ("PARTIAL" as const),
    note: curated ? r.method ?? "Dihitung dari resep standar beOkay." : "Nilai per 100 g bagian yang dapat dimakan. Konsisten secara internal (energi ≈ 4·protein + 9·lemak + 4·karbohidrat), bukan diperiksa manusia.",
  };
}

const STORAGE_LIMITS = { water: 100, calories: 950, protein: 100, fat: 100, carbohydrates: 100, fiber: 100, ash: 100 } as const;
type Per100 = Record<keyof typeof STORAGE_LIMITS, number | null>;

/**
 * Menyiapkan satu baris hasil parse untuk disimpan. Nilai di luar rentang yang masuk akal dikosongkan
 * (bukan dipotong atau ditebak) dan ditandai; baris seperti itu tidak mungkin `verified_auto`.
 */
export function sanitizeForStorage(row: { name: string; per100g: Per100; status: "verified_auto" | "needs_review"; flags: string[] }) {
  const per100g = { ...row.per100g };
  const flags = [...row.flags];
  let status = row.status;
  for (const key of Object.keys(STORAGE_LIMITS) as (keyof typeof STORAGE_LIMITS)[]) {
    const v = per100g[key];
    if (v !== null && (v < 0 || v > STORAGE_LIMITS[key])) {
      per100g[key] = null;
      flags.push(`VALUE_DROPPED_${key.toUpperCase()}`);
      status = "needs_review";
    }
  }
  if (status === "verified_auto" && [per100g.calories, per100g.protein, per100g.fat, per100g.carbohydrates].some((v) => v === null)) status = "needs_review";
  const name = row.name.replace(/\s+/g, " ").trim().slice(0, 200);
  return { name: name === "" ? "(tanpa nama)" : name, per100g, flags: [...new Set(flags)], status };
}
