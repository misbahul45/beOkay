import { buildFeatures, evaluate, type DayEvidence } from "../../src/features/ml/behavior/behavior.model.ts";

const users = Number(process.argv[2] ?? 40);
let seed = 42;
const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
const start = Date.UTC(2026, 6, 1);
const rows = Array.from({ length: users }, (_, u) => {
  const habit = rnd(), slotBias = ["MORNING", "AFTERNOON", "EVENING"][u % 3] as "MORNING" | "AFTERNOON" | "EVENING";
  const days: DayEvidence[] = Array.from({ length: 90 }, (_, i) => {
    const observed = rnd() > 0.15;
    return { localDate: new Date(start + i * 86_400_000).toISOString().slice(0, 10), observed, slots: observed ? { [slotBias]: rnd() < habit, MORNING: slotBias === "MORNING" ? rnd() < habit : rnd() < 0.1 } : {} };
  });
  return buildFeatures(`synthetic-${u}`, days, [], "2026-08-01", "2026-09-28");
}).flat();
console.log(JSON.stringify(evaluate(rows, { testUserFraction: 0.3, cutoff: "2026-09-01" }), null, 2));
