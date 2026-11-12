import { expect, test } from "bun:test";
import { routeMessage } from "../../src/features/conversation/conversation.router.ts";
import { CONVERSATION_CORPUS, type CorpusItem } from "../fixtures/conversation-corpus.ts";
import { matches } from "../support/corpus.ts";


const run = (item: CorpusItem) => routeMessage(item.text, item.ctx ?? { hasPreviousRun: false, lastRoute: null });

test("Korpus percakapan: ≥ 150 pesan beranotasi dengan semua rute utama", () => {
  expect(CONVERSATION_CORPUS.length).toBeGreaterThanOrEqual(150);
  const kinds = new Set(CONVERSATION_CORPUS.map((c) => c.expect.kind));
  for (const k of ["GREETING", "THANKS", "SUPPORT", "REFLECTION", "COMMUNITY", "HELP", "STATS", "ACTIVITY_PLAN", "FOOD", "MEAL_LOG", "SAFETY", "FOLLOW_UP", "UNKNOWN"]) expect(kinds.has(k)).toBe(true);
});

test("Router aturan: task success ≥ 90% pada pesan berlabel aturan, keselamatan, dan konteks", () => {
  const scoped = CONVERSATION_CORPUS.filter((c) => c.tags.some((t) => t === "rules" || t === "safety" || t === "context"));
  const misses = scoped.filter((c) => !matches(run(c), c)).map((c) => `${c.text} → ${run(c).kind}`);
  const success = 1 - misses.length / scoped.length;
  if (success < 0.9) console.log(misses);
  expect(success).toBeGreaterThanOrEqual(0.9);
  expect(scoped.filter((c) => c.tags.includes("safety")).every((c) => run(c).kind === "SAFETY")).toBe(true);
});

test("Baseline parafrase: sebagian besar parafrase jatuh ke UNKNOWN pada router aturan (alasan A-1)", () => {
  const para = CONVERSATION_CORPUS.filter((c) => c.tags.includes("paraphrase"));
  const unknown = para.filter((c) => run(c).kind === "UNKNOWN").length;
  console.log(JSON.stringify({ paraphrases: para.length, unknownRuleRouter: unknown }));
  expect(unknown / para.length).toBeGreaterThan(0.3);
  const off = CONVERSATION_CORPUS.filter((c) => c.tags.includes("offtopic")).map((c) => ({ text: c.text, kind: run(c).kind }));
  console.log(JSON.stringify({ offtopicFalsePositives: off.filter((o) => o.kind !== "UNKNOWN") }));
  expect(off.every((o) => ["UNKNOWN", "FOOD", "CLARIFY_FOOD"].includes(o.kind))).toBe(true);
  expect(off.filter((o) => o.kind !== "UNKNOWN").length).toBeLessThanOrEqual(2);
});
