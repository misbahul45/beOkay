import { env } from "../../src/config/env.ts";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { createEmbeddingClient, toVectorLiteral } from "../../src/features/food-reference/embedding.client.ts";
import { applyCuratedDishes } from "../../src/features/food-reference/curated.service.ts";

const embed = !process.argv.includes("--no-embed");
const result = await applyCuratedDishes();
console.log(JSON.stringify({ event: "curated_dishes_applied", applied: result.applied.length, skipped: result.skipped }));
if (embed) {
  const client = createEmbeddingClient({ apiKey: env.MISTRAL_API_KEY, model: env.MISTRAL_EMBEDDING_MODEL });
  if (!client.configured) {
    console.log(JSON.stringify({ event: "curated_embedding_skipped", reason: "MISTRAL_API_KEY tidak ada" }));
  } else {
    const todo = await prisma.$queryRaw<{ id: string; name: string }[]>`
      SELECT id::text AS id, name FROM food_reference
      WHERE status = 'curated' AND (embedding IS NULL OR embedding_model IS DISTINCT FROM ${client.model})
      ORDER BY code`;
    for (let i = 0; i < todo.length; i += 32) {
      const batch = todo.slice(i, i + 32);
      const vectors = await client.embed(batch.map((b) => b.name));
      await prisma.$transaction(batch.map((b, k) => prisma.$executeRaw`UPDATE food_reference SET embedding = ${toVectorLiteral(vectors[k]!)}::vector, embedding_model = ${client.model} WHERE id = ${b.id}::uuid`));
    }
    console.log(JSON.stringify({ event: "curated_embeddings_written", count: todo.length, model: client.model }));
  }
}
await prisma.$disconnect();
