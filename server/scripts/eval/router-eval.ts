import { env } from "../../src/config/env.ts";
import { routeMessage } from "../../src/features/conversation/conversation.router.ts";
import { createLlmRouter } from "../../src/features/conversation/intent-classifier.ts";
import { CONVERSATION_CORPUS, CONVERSATION_CORPUS_VERSION, HELD_OUT_CORPUS } from "../../tests/fixtures/conversation-corpus.ts";
import { BENIGN_ROUTES, INJECTION_CORPUS, INJECTION_CORPUS_VERSION } from "../../tests/fixtures/injection-corpus.ts";
import { matches } from "../../tests/support/corpus.ts";

if (!env.MISTRAL_API_KEY) {
  console.error("MISTRAL_API_KEY kosong: evaluasi dengan model sungguhan tidak bisa dijalankan.");
  process.exit(2);
}
const router = createLlmRouter({ apiKey: env.MISTRAL_API_KEY, model: env.MISTRAL_AGENT_MODEL, timeoutMs: 15_000 });
const pct = (a: number, b: number) => (b ? Math.round((a / b) * 1000) / 10 : null);
const latencies: number[] = [];

async function measure(items: typeof CONVERSATION_CORPUS) {
let unknownBefore = 0, unknownAfter = 0, correct = 0, wrong = 0, errors = 0, memoryProposed = 0;
const wrongItems: string[] = [];
for (const c of items) {
  if (c.tags.includes("safety") || c.tags.includes("context")) continue;
  const base = routeMessage(c.text, { hasPreviousRun: false, lastRoute: null });
  if (base.kind !== "UNKNOWN") continue;
  const target = c.expect.kind !== "UNKNOWN" && c.expect.kind !== "PREFERENCE";
  if (target) unknownBefore++;
  const out = await router.decide(c.text);
  latencies.push(out.log.latencyMs);
  if (out.log.decision === "ERROR") errors++;
  if (out.memory) memoryProposed++;
  const final = out.route ?? base;
  if (!target) {
    if (final.kind !== "UNKNOWN" && c.expect.kind === "UNKNOWN") wrongItems.push(`OFFTOPIC ${c.text} → ${final.kind}`);
    continue;
  }
  if (final.kind === "UNKNOWN") unknownAfter++;
  else if (matches(final, c)) correct++;
  else {
    wrong++;
    wrongItems.push(`${c.text} → ${final.kind}${final.kind === "STATS" ? ":" + final.domain : final.kind === "FOOD" ? ":" + final.query : ""} (harap ${c.expect.kind})`);
  }
}
return { paraphrasesUnknownBefore: unknownBefore, paraphrasesUnknownAfter: unknownAfter, unknownReductionPct: pct(unknownBefore - unknownAfter, unknownBefore), correctAfterHybrid: correct, wrongRoute: wrong, modelErrors: errors, memoryProposed, wrongItems };
}
const main = await measure(CONVERSATION_CORPUS);
const heldOut = await measure(HELD_OUT_CORPUS);

let violations = 0, held = 0, reachedModel = 0;
const violationItems: string[] = [];
for (const t of INJECTION_CORPUS) {
  const out = await router.decide(t);
  if (out.log.decision !== "REJECTED" || !["REGEX_BLOCKED", "INJECTION_PATTERN"].includes(out.log.rejectReason ?? "")) reachedModel++;
  if (out.log.decision === "HELD") held++;
  const kind = out.route?.kind ?? "UNKNOWN";
  if (!BENIGN_ROUTES.has(kind) || out.memory) {
    violations++;
    violationItems.push(`${t} → ${kind}${out.memory ? " +memori" : ""}`);
  }
}

latencies.sort((a, b) => a - b);
console.log(JSON.stringify({
  corpus: CONVERSATION_CORPUS_VERSION,
  injectionCorpus: INJECTION_CORPUS_VERSION,
  model: env.MISTRAL_AGENT_MODEL,
  corpusResult: main,
  heldOutResult: heldOut,
  latencyMs: { p50: latencies[Math.floor(latencies.length / 2)] ?? null, p95: latencies[Math.floor(latencies.length * 0.95)] ?? null },
  injections: INJECTION_CORPUS.length,
  injectionsReachedModel: reachedModel,
  injectionsHeldByJudge: held,
  gateViolations: violations,
  violationItems,
}, null, 2));
