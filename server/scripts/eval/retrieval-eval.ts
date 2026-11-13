import { knowledgeService } from "../../src/features/knowledge/knowledge.service.ts";
import { RETRIEVAL_QUERIES } from "../../tests/fixtures/retrieval-queries.ts";

const K = Number(process.argv[2] ?? 3);
await knowledgeService.sync();
let recallSum = 0, rr = 0, answerable = 0, correctAbstain = 0, wrongAnswer = 0, unanswerable = 0;
const rows: string[] = [];
for (const q of RETRIEVAL_QUERIES) {
  const r = await knowledgeService.retrieve({ query: q.query, lane: q.lane, journey: q.journey, limit: K, includeDrafts: true });
  const got = r.items.map((i) => i.slug);
  if (!q.relevant.length) {
    unanswerable++;
    if (r.decision.status === "ABSTAIN") correctAbstain++;
    else wrongAnswer++;
    rows.push(`${r.decision.status === "ABSTAIN" ? "ok  " : "FAIL"} abstain  ${q.query}`);
    continue;
  }
  answerable++;
  const hits = q.relevant.filter((s) => got.includes(s)).length;
  recallSum += hits / Math.min(q.relevant.length, K);
  const first = got.findIndex((s) => q.relevant.includes(s));
  rr += first >= 0 ? 1 / (first + 1) : 0;
  rows.push(`${first >= 0 ? "ok  " : "MISS"} ${r.decision.status.padEnd(7)} ${q.query} -> ${got.join(", ") || "-"}`);
}
console.log(rows.join("\n"));
console.log(JSON.stringify({ k: K, answerable, unanswerable, recallAtK: Math.round((recallSum / answerable) * 1000) / 1000, mrr: Math.round((rr / answerable) * 1000) / 1000, correctAbstain, wrongAnswer, note: "Set kueri kecil yang ditulis tim; dilaporkan apa adanya, tanpa ambang." }, null, 2));
process.exit(0);
