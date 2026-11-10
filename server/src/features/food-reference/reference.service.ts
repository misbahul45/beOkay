import { Prisma } from "../../generated/prisma/client.ts";
import { env } from "../../config/env.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { ProviderError } from "../food-discovery/food-candidate.ts";
import { normalizeTerm } from "../food-preferences/food-preferences.model.ts";
import { createEmbeddingClient, toVectorLiteral } from "./embedding.client.ts";
import { reciprocalRankFusion, toReferenceFood, type ReferenceRow } from "./reference.model.ts";

type Embedder = Pick<ReturnType<typeof createEmbeddingClient>, "embed" | "configured">;
type Db = Pick<typeof prisma, "$queryRaw">;

const COLUMNS = Prisma.sql`id::text AS id, code, name, source_ref AS "sourceRef", page, chapter,
  water::float8 AS water, calories::float8 AS calories, protein::float8 AS protein, fat::float8 AS fat,
  carbohydrates::float8 AS carbohydrates, fiber::float8 AS fiber, ash::float8 AS ash`;

/** Hanya baris verified_auto yang pernah keluar dari pencarian. needs_review disimpan tetapi tidak dipakai. */
export function createReferenceService(deps: { embedder: Embedder; db?: Db; minSimilarity?: number; cacheSize?: number }) {
  const db = deps.db ?? prisma;
  // 0,75 dikalibrasi pada 14 kueri nyata: kueri relevan puncaknya 0,77–0,91, kueri tak bermakna 0,64–0,72 (heuristik, bukan evaluasi terukur).
  const minSimilarity = deps.minSimilarity ?? 0.75;
  const cache = new Map<string, number[]>();
  const cacheSize = deps.cacheSize ?? 200;

  async function queryVector(q: string): Promise<number[] | null> {
    const hit = cache.get(q);
    if (hit) return hit;
    try {
      const [v] = await deps.embedder.embed([q]);
      if (!v) return null;
      if (cache.size >= cacheSize) cache.delete(cache.keys().next().value!);
      cache.set(q, v);
      return v;
    } catch (e) {
      if (e instanceof ProviderError) return null; // pencarian leksikal tetap jalan
      throw e;
    }
  }

  return {
    async search(rawQuery: string, limit = 10) {
      const q = normalizeTerm(rawQuery);
      if (q.length < 2) return { status: "OK" as const, items: [] as ReturnType<typeof withMeta>[] };
      const like = `%${q.replace(/[\\%_]/g, "\\$&")}%`;
      const lexical = await db.$queryRaw<(ReferenceRow & { score: number })[]>(Prisma.sql`
        SELECT ${COLUMNS}, GREATEST(word_similarity(${q}, name_normalized), CASE WHEN name_normalized LIKE ${like} THEN 0.7 ELSE 0 END)::float8 AS score
        FROM food_reference
        WHERE status = 'verified_auto' AND (name_normalized LIKE ${like} OR word_similarity(${q}, name_normalized) >= 0.45)
        ORDER BY score DESC, name ASC LIMIT ${limit * 2}`);

      let semantic: (ReferenceRow & { score: number })[] = [];
      let semanticAvailable = false;
      if (deps.embedder.configured) {
        const vec = await queryVector(q);
        if (vec) {
          semanticAvailable = true;
          const literal = toVectorLiteral(vec);
          semantic = await db.$queryRaw<(ReferenceRow & { score: number })[]>(Prisma.sql`
            SELECT ${COLUMNS}, (1 - (embedding <=> ${literal}::vector))::float8 AS score
            FROM food_reference
            WHERE status = 'verified_auto' AND embedding IS NOT NULL
            ORDER BY embedding <=> ${literal}::vector ASC LIMIT ${limit * 2}`);
          semantic = semantic.filter((r) => r.score >= minSimilarity);
        }
      }
      const fused = reciprocalRankFusion(
        [
          { name: "lexical", items: lexical },
          { name: "semantic", items: semantic },
        ],
        limit,
      );
      return {
        status: semanticAvailable ? ("OK" as const) : ("LEXICAL_ONLY" as const),
        items: fused.map(withMeta),
      };
    },
  };
}

function withMeta(r: ReferenceRow & { score: number; matchedBy: string[] }) {
  return { ...toReferenceFood(r), score: r.score, matchedBy: r.matchedBy };
}

export const referenceService = createReferenceService({
  embedder: createEmbeddingClient({ apiKey: env.MISTRAL_API_KEY, model: env.MISTRAL_EMBEDDING_MODEL }),
});
