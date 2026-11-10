/**
 * Memuat hasil parse TKPI ke tabel food_reference dan membuat embedding (mistral-embed) untuk baris verified_auto.
 *
 *   bun run scripts/tkpi/ingest.ts <parsed.json> [--no-embed]
 *
 * parsed.json = keluaran parseTkpi().rows (lihat scripts/tkpi/parse.ts). Idempoten: upsert per `code`;
 * embedding hanya dibuat untuk baris yang belum punya (atau berganti model). Kunci dibaca dari env, tidak dicetak.
 */
import { env } from "../../src/config/env.ts";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { createEmbeddingClient, toVectorLiteral } from "../../src/features/food-reference/embedding.client.ts";
import { REFERENCE_SOURCE, REFERENCE_VERSION, sanitizeForStorage } from "../../src/features/food-reference/reference.model.ts";
import { normalizeTerm } from "../../src/features/food-preferences/food-preferences.model.ts";
import type { TkpiRow } from "../../src/features/food-reference/tkpi-parser.ts";

const path = process.argv[2];
const embed = !process.argv.includes("--no-embed");
if (!path) throw new Error("Pemakaian: bun run scripts/tkpi/ingest.ts <parsed.json> [--no-embed]");
const rows = (await Bun.file(path).json()) as TkpiRow[];
if (!Array.isArray(rows) || rows.length === 0) throw new Error("parsed.json kosong atau bukan daftar baris.");

let upserted = 0;
for (let i = 0; i < rows.length; i += 100) {
  const batch = rows.slice(i, i + 100);
  await prisma.$transaction(
    batch.map((raw) => {
      const clean = sanitizeForStorage(raw);
      const r = { ...raw, ...clean };
      const data = {
        name: r.name,
        nameNormalized: normalizeTerm(r.name),
        source: REFERENCE_SOURCE,
        sourceVersion: REFERENCE_VERSION,
        sourceRef: r.sourceRef,
        page: r.page,
        chapter: r.chapter,
        status: r.status,
        flags: r.flags,
        water: r.per100g.water,
        calories: r.per100g.calories,
        protein: r.per100g.protein,
        fat: r.per100g.fat,
        carbohydrates: r.per100g.carbohydrates,
        fiber: r.per100g.fiber,
        ash: r.per100g.ash,
      };
      return prisma.foodReference.upsert({ where: { code: r.code }, create: { code: r.code, ...data }, update: data });
    }),
  );
  upserted += batch.length;
}
const verified = rows.filter((r) => sanitizeForStorage(r).status === "verified_auto").length;
console.log(JSON.stringify({ event: "tkpi_rows_upserted", total: upserted, verified_auto: verified, needs_review: upserted - verified }));

if (embed) {
  const client = createEmbeddingClient({ apiKey: env.MISTRAL_API_KEY, model: env.MISTRAL_EMBEDDING_MODEL });
  if (!client.configured) {
    console.log(JSON.stringify({ event: "tkpi_embedding_skipped", reason: "MISTRAL_API_KEY tidak ada" }));
  } else {
    const todo = await prisma.$queryRaw<{ id: string; name: string }[]>`
      SELECT id::text AS id, name FROM food_reference
      WHERE status = 'verified_auto' AND (embedding IS NULL OR embedding_model IS DISTINCT FROM ${client.model})
      ORDER BY code`;
    let done = 0;
    for (let i = 0; i < todo.length; i += 32) {
      const batch = todo.slice(i, i + 32);
      const vectors = await client.embed(batch.map((b) => b.name));
      await prisma.$transaction(
        batch.map((b, k) => prisma.$executeRaw`UPDATE food_reference SET embedding = ${toVectorLiteral(vectors[k]!)}::vector, embedding_model = ${client.model} WHERE id = ${b.id}::uuid`),
      );
      done += batch.length;
    }
    console.log(JSON.stringify({ event: "tkpi_embeddings_written", count: done, model: client.model }));
  }
}
await prisma.$disconnect();
