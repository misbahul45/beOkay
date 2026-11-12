import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { TOP_QUERIES } from "../../src/content/food/curated-dishes.ts";
import { referenceService } from "../../src/features/food-reference/reference.service.ts";
import { normalizeTerm } from "../../src/features/food-preferences/food-preferences.model.ts";

export function isHit(query: string, names: string[]) {
  const tokens = normalizeTerm(query).replace(/-/g, " ").split(" ").filter(Boolean);
  return names.some((n) => {
    const name = normalizeTerm(n).replace(/-/g, " ");
    return tokens.every((t) => name.includes(t));
  });
}

const rows: { query: string; hit: boolean; top: string | null; curated: boolean }[] = [];
for (const q of TOP_QUERIES) {
  const r = await referenceService.search(q, 5);
  const names = r.items.map((i) => i.name);
  const first = r.items.find((i) => isHit(q, [i.name]));
  rows.push({ query: q, hit: Boolean(first), top: first?.name ?? null, curated: first?.verification === "curated" });
}
const hits = rows.filter((r) => r.hit).length;
console.log(JSON.stringify({ event: "food_search_hit_rate", hits, total: rows.length, rate: Math.round((hits / rows.length) * 1000) / 10, curatedHits: rows.filter((r) => r.curated).length, rows }, null, 2));
await prisma.$disconnect();
