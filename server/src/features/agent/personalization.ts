import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { normalizeTerm } from "../food-preferences/food-preferences.model.ts";

/**
 * Personalisasi DETERMINISTIK dan berversi (bukan pembelajaran mesin): penolakan menambah bobot pada kata nama
 * makanan yang ditolak; bobot itu menurunkan peringkat kandidat serupa. Setiap perubahan menaikkan versi dan
 * tercatat di personalization_events sehingga perubahan peringkat dapat dijelaskan dan dihapus pengguna.
 * v2: kata dari makanan yang TERUKUR benar-benar dimakan (ada di catatan makan setelah rencana diterima) menaikkan peringkat
 * dengan bonus kecil; bila catatan itu kemudian diarsipkan, bonusnya ditarik kembali.
 */
export const PERSONALIZATION_RULES_VERSION = "pref-rules-v2";
export const MAX_WEIGHT = 5;
// Satu penolakan harus terasa: skor dasar 1/(peringkat+1) sehingga 0,6 menurunkan butir peringkat 1 di bawah peringkat 2. Dapat direset pengguna.
export const PENALTY_PER_WEIGHT = 0.6;
// Bonus lebih kecil dari penalti: bukti "pernah dimakan" tidak boleh mengalahkan penolakan eksplisit.
export const BOOST_PER_WEIGHT = 0.2;

const STOP = new Set(["dan", "atau", "yang", "dengan", "untuk", "segar", "kering", "masakan", "goreng", "rebus", "bakar", "kukus", "biji", "dari", "pada"]);

export type ProfileData = { dislikedTokens: Record<string, { weight: number; rejections: number }>; likedTokens: Record<string, { weight: number; observations: number }> };
export type Profile = { version: number; data: ProfileData };

export function tokensOf(name: string, exclude: string[] = []): string[] {
  const ex = new Set(exclude.flatMap((e) => normalizeTerm(e).split(" ")));
  return [...new Set(normalizeTerm(name).split(" ").filter((t) => t.length >= 4 && !STOP.has(t) && !ex.has(t)))];
}

/** Penalti peringkat dan alasan yang dapat ditampilkan. */
export function penaltyFor(name: string, profile: Profile): { penalty: number; matched: string[] } {
  const matched: string[] = [];
  let penalty = 0;
  for (const t of tokensOf(name)) {
    const w = profile.data.dislikedTokens[t]?.weight ?? 0;
    if (w > 0) {
      matched.push(t);
      penalty += w * PENALTY_PER_WEIGHT;
    }
  }
  return { penalty: Math.round(penalty * 1000) / 1000, matched };
}

/** Bonus peringkat dari makanan yang terukur dimakan, dan kata yang menyebabkannya. */
export function boostFor(name: string, profile: Profile): { boost: number; matched: string[] } {
  const matched: string[] = [];
  let boost = 0;
  for (const t of tokensOf(name)) {
    const w = profile.data.likedTokens[t]?.weight ?? 0;
    if (w > 0) {
      matched.push(t);
      boost += w * BOOST_PER_WEIGHT;
    }
  }
  return { boost: Math.round(boost * 1000) / 1000, matched };
}

const empty = (): ProfileData => ({ dislikedTokens: {}, likedTokens: {} });
const parse = (raw: unknown): ProfileData => {
  const d = raw as Partial<ProfileData> | null;
  return d && typeof d === "object" && d.dislikedTokens && typeof d.dislikedTokens === "object" ? { dislikedTokens: d.dislikedTokens, likedTokens: d.likedTokens && typeof d.likedTokens === "object" ? d.likedTokens : {} } : empty();
};

export const personalization = {
  async get(userId: string, db: Prisma.TransactionClient | typeof prisma = prisma): Promise<Profile> {
    const row = await db.personalizationProfile.findUnique({ where: { userId } });
    return row ? { version: row.version, data: parse(row.data) } : { version: 0, data: empty() };
  },

  /** Penolakan kandidat: bobot kata naik (maks 5), versi naik, peristiwa dicatat. Dipanggil di dalam transaksi keputusan. */
  async applyRejection(tx: Prisma.TransactionClient, userId: string, recommendationId: string, candidateName: string, queryTerms: string[]) {
    const tokens = tokensOf(candidateName, queryTerms);
    if (tokens.length === 0) return null;
    await tx.personalizationProfile.upsert({ where: { userId }, create: { userId, version: 0, data: empty() as object }, update: {} });
    const current = await tx.personalizationProfile.findUniqueOrThrow({ where: { userId } });
    const data = parse(current.data);
    const change: Record<string, { from: number; to: number }> = {};
    for (const t of tokens) {
      const prev = data.dislikedTokens[t] ?? { weight: 0, rejections: 0 };
      const next = { weight: Math.min(MAX_WEIGHT, prev.weight + 1), rejections: prev.rejections + 1 };
      data.dislikedTokens[t] = next;
      change[t] = { from: prev.weight, to: next.weight };
    }
    const updated = await tx.personalizationProfile.update({ where: { userId }, data: { data: data as object, version: { increment: 1 } } });
    await tx.personalizationEvent.create({
      data: { userId, version: updated.version, reason: "RECOMMENDATION_REJECTED", sourceRecommendationId: recommendationId, change: { rules: PERSONALIZATION_RULES_VERSION, tokens: change } },
    });
    return { version: updated.version, change };
  },

  /** Hasil terukur: makanan yang direncanakan benar-benar tercatat dimakan (+1) atau buktinya ditarik (-1). Idempoten lewat `sourceKey` (satu peristiwa per kunci). */
  async applyOutcome(userId: string, recommendationId: string, foodName: string, direction: 1 | -1) {
    const tokens = tokensOf(foodName);
    if (tokens.length === 0) return null;
    return prisma.$transaction(async (tx) => {
      await tx.personalizationProfile.upsert({ where: { userId }, create: { userId, version: 0, data: empty() as object }, update: {} });
      const current = await tx.personalizationProfile.findUniqueOrThrow({ where: { userId } });
      const data = parse(current.data);
      const change: Record<string, { from: number; to: number }> = {};
      for (const t of tokens) {
        const prev = data.likedTokens[t] ?? { weight: 0, observations: 0 };
        const next = { weight: Math.max(0, Math.min(MAX_WEIGHT, prev.weight + direction)), observations: Math.max(0, prev.observations + direction) };
        if (next.weight === 0 && next.observations === 0) delete data.likedTokens[t];
        else data.likedTokens[t] = next;
        change[t] = { from: prev.weight, to: next.weight };
      }
      const updated = await tx.personalizationProfile.update({ where: { userId }, data: { data: data as object, version: { increment: 1 } } });
      await tx.personalizationEvent.create({ data: { userId, version: updated.version, reason: direction === 1 ? "OUTCOME_OBSERVED" : "OUTCOME_RETRACTED", sourceRecommendationId: recommendationId, change: { rules: PERSONALIZATION_RULES_VERSION, liked: change } } });
      return { version: updated.version, change };
    });
  },

  /** Pengguna menghapus hasil pembelajaran: kembali ke data kosong, versi tetap naik agar riwayat dapat diaudit. */
  async reset(userId: string) {
    return prisma.$transaction(async (tx) => {
      await tx.personalizationProfile.upsert({ where: { userId }, create: { userId, version: 0, data: empty() as object }, update: {} });
      const updated = await tx.personalizationProfile.update({ where: { userId }, data: { data: empty() as object, version: { increment: 1 } } });
      await tx.personalizationEvent.create({ data: { userId, version: updated.version, reason: "USER_RESET", change: { rules: PERSONALIZATION_RULES_VERSION, cleared: true } } });
      return { version: updated.version };
    });
  },

  async summary(userId: string) {
    const p = await this.get(userId);
    return {
      version: p.version,
      rulesVersion: PERSONALIZATION_RULES_VERSION,
      method: "DETERMINISTIC_RULES",
      dislikedTerms: Object.entries(p.data.dislikedTokens).map(([term, v]) => ({ term, weight: v.weight, rejections: v.rejections })).sort((a, b) => b.weight - a.weight || a.term.localeCompare(b.term)),
      likedTerms: Object.entries(p.data.likedTokens).map(([term, v]) => ({ term, weight: v.weight, observations: v.observations })).sort((a, b) => b.weight - a.weight || a.term.localeCompare(b.term)),
    };
  },
};
