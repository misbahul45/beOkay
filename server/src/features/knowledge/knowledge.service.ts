import { createHash } from "node:crypto";
import { env } from "../../config/env.ts";
import { EDUCATION_MODULES, MODULE_JOURNEYS } from "../../content/education/modules.ts";
import { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
import { logEvent } from "../../shared/http/logger.ts";
import type { Journey } from "../cohort/cohort.policy.ts";
import { BARRIER_LABEL, BARRIERS, STRATEGIES, strategyJourneys } from "../coaching/coaching.strategies.ts";
import { createEmbeddingClient, toVectorLiteral } from "../food-reference/embedding.client.ts";
import { assessCoverage, certaintyOf, chunkMarkdown, type Certainty, type CoverageDecision, fuse, normalizeText, RETRIEVAL_VERSION, sourceOf } from "./knowledge.model.ts";

export type Lane = "A_PUBLIC_HEALTH" | "C_BEHAVIOR_STRATEGY";

type DocSpec = {
  lane: Lane;
  slug: string;
  title: string;
  sourceName: string;
  publisher: string;
  allowedJourneys: readonly string[];
  topics: string[];
  chunks: string[];
};

const STOP = new Set(["yang", "untuk", "dengan", "bagaimana", "gimana", "apakah", "tentang", "saya", "aku", "kamu", "bisa", "agar", "supaya", "cara", "kalau", "dari", "pada", "atau", "juga", "tolong", "jelaskan", "dong", "sih", "nggak", "tidak", "sudah", "lagi", "mau", "ingin", "biar", "harus", "perlu", "hari", "minggu", "sekarang", "the", "and"]);

export function queryTerms(q: string): string[] {
  return [...new Set(normalizeText(q).split(" ").filter((w) => w.length >= 4 && !STOP.has(w)))].slice(0, 8);
}

export function lexicalScore(terms: string[], text: string): number {
  if (!terms.length) return 0;
  const words = text.split(" ");
  let hit = 0;
  for (const t of terms) if (words.some((w) => w === t || (t.length >= 5 && (w.startsWith(t.slice(0, Math.max(5, t.length - 2))) || t.startsWith(w) && w.length >= 5)))) hit++;
  return hit / terms.length;
}

function educationDocs(): DocSpec[] {
  return EDUCATION_MODULES.map((m) => {
    const sections = chunkMarkdown(m.body);
    return {
      lane: "A_PUBLIC_HEALTH" as const,
      slug: `edu:${m.key}@v${m.version}`,
      title: m.title,
      sourceName: sourceOf(sections),
      publisher: "beOkay (ringkasan dari sumber yang disebut)",
      allowedJourneys: MODULE_JOURNEYS[m.key] ?? ["T2DM_SUPPORT", "UNDETERMINED"],
      topics: m.topics,
      chunks: [m.summary, ...sections.filter((s) => s.heading.toLowerCase() !== "sumber").map((s) => `${s.heading}: ${s.text}`)],
    };
  });
}

export const BARRIER_VOCAB: Record<string, string[]> = {
  TIME: ["waktu", "sibuk", "sempat", "kerja", "lembur"],
  FORGOT: ["lupa", "kelupaan", "terlewat"],
  ENERGY: ["capek", "lelah", "letih", "lemas", "tenaga", "bertenaga"],
  MOTIVATION: ["malas", "bosan", "semangat", "motivasi", "konsisten"],
  OTHER: [],
};

function strategyDocs(): DocSpec[] {
  return BARRIERS.flatMap((b) =>
    STRATEGIES[b].map((s) => ({
      lane: "C_BEHAVIOR_STRATEGY" as const,
      slug: `strategy:${s.key}@v1`,
      title: s.title,
      sourceName: "Katalog strategi beOkay (strategy-catalog-v1)",
      publisher: "beOkay",
      allowedJourneys: strategyJourneys(s.key),
      topics: ["hambatan", b.toLowerCase(), BARRIER_LABEL[b].toLowerCase(), ...(BARRIER_VOCAB[b] ?? [])],
      chunks: [`${s.title}. ${s.detail} Hambatan: ${BARRIER_LABEL[b]}.`],
    })),
  );
}

export const knowledgeEmbedder = { current: createEmbeddingClient({ apiKey: env.MISTRAL_API_KEY, model: env.MISTRAL_EMBEDDING_MODEL }) as Pick<ReturnType<typeof createEmbeddingClient>, "embed" | "configured"> };

const hashOf = (d: DocSpec) => createHash("sha256").update(JSON.stringify([d.title, d.sourceName, d.allowedJourneys, d.topics, d.chunks])).digest("hex");

export type RetrievedItem = {
  documentId: string;
  slug: string;
  lane: Lane;
  title: string;
  text: string;
  sourceName: string;
  reviewStatus: string;
  certainty: Certainty;
  score: number;
  matchedBy: ("lexical" | "vector")[];
};

export type RetrievalResult = {
  version: string;
  lane: Lane;
  journey: Journey;
  decision: CoverageDecision;
  certainty: Certainty;
  items: RetrievedItem[];
  pipeline: string[];
};

export const knowledgeService = {
  async sync() {
    const specs = [...educationDocs(), ...strategyDocs()];
    const reviewed = new Map((await prisma.educationModule.findMany({ where: { reviewStatus: "REVIEWED" } })).map((r) => [`edu:${r.key}@v${r.version}`, r]));
    const result = { created: 0, updated: 0, unchanged: 0 };
    for (const d of specs) {
      const contentHash = hashOf(d);
      const rev = reviewed.get(d.slug);
      const review = rev ? { reviewStatus: "REVIEWED", reviewedAt: rev.reviewedAt, reviewer: rev.reviewedBy } : {};
      const existing = await prisma.knowledgeDocument.findUnique({ where: { slug: d.slug } });
      if (existing && existing.contentHash === contentHash) {
        if (rev && existing.reviewStatus !== "REVIEWED") await prisma.knowledgeDocument.update({ where: { id: existing.id }, data: review });
        result.unchanged++;
        continue;
      }
      await prisma.$transaction(async (tx) => {
        const data = { lane: d.lane, title: d.title, sourceName: d.sourceName, publisher: d.publisher, allowedJourneys: [...d.allowedJourneys], topics: d.topics, contentHash, ...review };
        const doc = existing
          ? await tx.knowledgeDocument.update({ where: { id: existing.id }, data: { ...data, version: { increment: 1 }, ...(rev ? {} : { reviewStatus: "DRAFT", reviewedAt: null, reviewer: null }) } })
          : await tx.knowledgeDocument.create({ data: { slug: d.slug, ...data } });
        await tx.knowledgeChunk.deleteMany({ where: { documentId: doc.id } });
        await tx.knowledgeChunk.createMany({ data: d.chunks.map((text, ordinal) => ({ documentId: doc.id, ordinal, text, textNormalized: normalizeText(`${d.title} ${text} ${d.topics.join(" ")}`) })) });
      });
      existing ? result.updated++ : result.created++;
    }
    const embedded = await this.embedMissing();
    return { ...result, embedded };
  },

  async embedMissing(limit = 64) {
    if (!knowledgeEmbedder.current.configured) return 0;
    const rows = await prisma.$queryRaw<{ id: string; text_normalized: string }[]>`SELECT id, text_normalized FROM knowledge_chunks WHERE embedding IS NULL ORDER BY created_at LIMIT ${limit}`;
    if (!rows.length) return 0;
    try {
      const vectors = await knowledgeEmbedder.current.embed(rows.map((r) => r.text_normalized));
      for (let i = 0; i < rows.length; i++) await prisma.$executeRaw`UPDATE knowledge_chunks SET embedding = ${toVectorLiteral(vectors[i]!)}::vector, embedding_model = ${env.MISTRAL_EMBEDDING_MODEL} WHERE id = ${rows[i]!.id}::uuid`;
      return rows.length;
    } catch (e) {
      logEvent("warn", "knowledge_embedding_failed", { name: e instanceof Error ? e.name : "unknown" });
      return 0;
    }
  },

  async retrieve(input: { query: string; lane: Lane; journey: Journey; limit?: number; includeDrafts?: boolean; now?: Date }): Promise<RetrievalResult> {
    const limit = Math.min(input.limit ?? 3, 5);
    const draftsAllowed = input.includeDrafts ?? env.EDUCATION_INCLUDE_DRAFTS;
    const statuses = draftsAllowed ? ["REVIEWED", "DRAFT"] : ["REVIEWED"];
    const now = input.now ?? new Date();
    const pipeline = ["normalize", "filter:lane", "filter:journey", "filter:language", "filter:review_status", "filter:expiry"];
    const terms = queryTerms(input.query);
    const docs = await prisma.knowledgeDocument.findMany({
      where: { lane: input.lane, language: "id", reviewStatus: { in: statuses }, allowedJourneys: { has: input.journey }, OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
      include: { chunks: { select: { id: true, text: true, textNormalized: true } } },
    });
    const chunkMeta = new Map(docs.flatMap((d) => d.chunks.map((c) => [c.id, { doc: d, chunk: c }] as const)));
    pipeline.push("lexical");
    const lexical = [...chunkMeta.entries()]
      .map(([id, { chunk }]) => ({ id, score: lexicalScore(terms, chunk.textNormalized) }))
      .filter((r) => r.score > 0)
      .sort((a, b) => b.score - a.score || a.id.localeCompare(b.id))
      .slice(0, 20);
    let vector: { id: string; score: number }[] = [];
    if (knowledgeEmbedder.current.configured && chunkMeta.size) {
      pipeline.push("vector");
      try {
        const [v] = await knowledgeEmbedder.current.embed([normalizeText(input.query)]);
        const ids = [...chunkMeta.keys()];
        vector = (await prisma.$queryRaw<{ id: string; score: number }[]>`
          SELECT id, (1 - (embedding <=> ${toVectorLiteral(v!)}::vector))::float8 AS score FROM knowledge_chunks
          WHERE embedding IS NOT NULL AND id IN (${Prisma.join(ids.map((i) => Prisma.sql`${i}::uuid`))})
          ORDER BY embedding <=> ${toVectorLiteral(v!)}::vector ASC LIMIT 20`).filter((r) => r.score > 0);
      } catch (e) {
        pipeline.push("vector:failed");
        logEvent("warn", "knowledge_vector_failed", { name: e instanceof Error ? e.name : "unknown" });
      }
    }
    pipeline.push("rrf", "filter:freshness", "rerank:off", "coverage");
    const lexMap = new Map(lexical.map((r) => [r.id, r.score]));
    const vecMap = new Map(vector.map((r) => [r.id, r.score]));
    const fused = fuse([lexical, vector]);
    const perDoc = new Set<string>();
    const items: RetrievedItem[] = [];
    for (const f of fused) {
      const meta = chunkMeta.get(f.id)!;
      const lex = lexMap.get(f.id) ?? null, vec = vecMap.get(f.id) ?? null;
      if ((lex ?? 0) < 0.3 && (vec ?? 0) < 0.75) continue;
      if (perDoc.has(meta.doc.id)) continue;
      perDoc.add(meta.doc.id);
      items.push({
        documentId: meta.doc.id,
        slug: meta.doc.slug,
        lane: meta.doc.lane as Lane,
        title: meta.doc.title,
        text: meta.chunk.text,
        sourceName: meta.doc.sourceName,
        reviewStatus: meta.doc.reviewStatus,
        certainty: certaintyOf({ kind: "knowledge", reviewStatus: meta.doc.reviewStatus }),
        score: Math.round(f.score * 10000) / 10000,
        matchedBy: [...(lex !== null ? ["lexical" as const] : []), ...(vec !== null ? ["vector" as const] : [])],
      });
      if (items.length >= limit) break;
    }
    const best = items[0] ? { lexical: lexMap.get(fused.find((f) => chunkMeta.get(f.id)!.doc.id === items[0]!.documentId)!.id) ?? null, vector: vecMap.get(fused.find((f) => chunkMeta.get(f.id)!.doc.id === items[0]!.documentId)!.id) ?? null } : null;
    const decision = assessCoverage(best, { reviewedCount: items.filter((i) => i.reviewStatus === "REVIEWED").length, draftsAllowed });
    const answered = decision.status === "ANSWER";
    return {
      version: RETRIEVAL_VERSION,
      lane: input.lane,
      journey: input.journey,
      decision,
      certainty: answered ? (items.every((i) => i.certainty === "verified") ? "verified" : "insufficient") : "unknown",
      items: answered ? items : [],
      pipeline,
    };
  },
};
