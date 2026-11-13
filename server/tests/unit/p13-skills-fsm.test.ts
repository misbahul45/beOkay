import { describe, expect, test } from "bun:test";
import { canTransition, createMachine, FSM_STATES, FsmError, pathFor, TERMINAL, TRANSITIONS, type FsmState } from "../../src/features/agent/agent.fsm.ts";
import { GLOBAL_PROHIBITED, MAX_SKILLS_PER_MESSAGE, orderByDependencies, selectSkills, SKILLS, skillById, validateRegistry } from "../../src/features/agent/skills/registry.ts";
import { TOOL_NAMES, TOOL_CONTRACTS, CONFIRMED_ACTIONS } from "../../src/features/agent/agent.tools.ts";
import { classifyBarrier } from "../../src/features/agent/skills/runner.ts";
import { assessCoverage, certaintyOf, chunkMarkdown, fuse, normalizeText, sourceOf } from "../../src/features/knowledge/knowledge.model.ts";
import { lexicalScore, queryTerms } from "../../src/features/knowledge/knowledge.service.ts";
import { addDays, assessSleep, assessSteps, assessWorkouts, summarize } from "../../src/features/devices/quality.model.ts";
import { secondaryRoutes } from "../../src/features/conversation/conversation.skills.ts";
import { routeMessage } from "../../src/features/conversation/conversation.router.ts";

const ALL = new Set(["health_data_processing", "descriptive_summaries", "personalized_ai", "device_data_coaching"]);

describe("skills-v1 registri", () => {
  test("8 skill dengan atribut wajib; validator tidak menemukan masalah", () => {
    expect(SKILLS.map((s) => s.id).sort()).toEqual(["activity.planner", "behavior.barrier_solver", "health.trend_explainer", "memory.reflector", "nutrition.coach", "prevention.education", "sleep.recovery", "social.challenge_coach"]);
    expect(validateRegistry(SKILLS, TOOL_NAMES)).toEqual([]);
    for (const s of SKILLS) {
      expect(s.maxIterations).toBeLessThanOrEqual(3);
      expect(s.maxToolCalls).toBeLessThanOrEqual(8);
      expect(s.prohibitedActions).toEqual(expect.arrayContaining([...GLOBAL_PROHIBITED]));
      for (const t of s.allowedTools) expect(TOOL_CONTRACTS.find((c) => c.name === t)!.tier).toBe("READ_ONLY");
      for (const a of s.confirmedActions) expect(a in CONFIRMED_ACTIONS).toBe(true);
    }
  });

  test("validator menangkap pelanggaran: alat tak dikenal, alat terlarang, rute ganda, jalur UNDETERMINED, anggaran", () => {
    const bad = { ...skillById("sleep.recovery")!, id: "x.y", allowedTools: ["raw_query", "nope"], routes: ["SLEEP"] as const, allowedJourneys: ["UNDETERMINED"] as const, maxIterations: 5, maxToolCalls: 9, requiredConsents: [] };
    const problems = validateRegistry([...SKILLS, bad as never], TOOL_NAMES);
    expect(problems).toEqual(expect.arrayContaining(["UNKNOWN_TOOL:x.y:raw_query", "PROHIBITED_TOOL:x.y:raw_query", "UNKNOWN_TOOL:x.y:nope", "ROUTE_CLAIMED_TWICE:SLEEP", "UNDETERMINED_NOT_ALLOWED:x.y", "ITERATIONS_OUT_OF_RANGE:x.y", "TOOL_BUDGET_OUT_OF_RANGE:x.y", "MISSING_BASE_CONSENT:x.y"]));
  });

  test("pemilihan: di luar registri, jalur, atau consent ditolak beralasan; maksimum 2 skill; urutan dependensi", () => {
    expect(selectSkills(["tidak.ada"], { journey: "WELLNESS", consents: ALL, enabled: true }).denied).toEqual([{ skillId: "tidak.ada", reason: "UNKNOWN_SKILL" }]);
    expect(selectSkills(["prevention.education"], { journey: "T2DM_SUPPORT", consents: ALL, enabled: true }).denied[0]).toMatchObject({ reason: "JOURNEY_NOT_ALLOWED" });
    expect(selectSkills(["prevention.education"], { journey: "PREVENTION", consents: ALL, enabled: true }).skills.map((s) => s.id)).toEqual(["prevention.education"]);
    for (const s of SKILLS) expect(selectSkills([s.id], { journey: "UNDETERMINED", consents: ALL, enabled: true }).skills).toEqual([]);
    expect(selectSkills(["sleep.recovery"], { journey: "WELLNESS", consents: new Set(["health_data_processing"]), enabled: true }).denied[0]).toEqual({ skillId: "sleep.recovery", reason: "CONSENT_REQUIRED", detail: "descriptive_summaries" });
    const three = selectSkills(["memory.reflector", "health.trend_explainer", "sleep.recovery"], { journey: "WELLNESS", consents: ALL, enabled: true });
    expect(three.skills.length).toBe(MAX_SKILLS_PER_MESSAGE);
    expect(three.skills.map((s) => s.id)).toEqual(["health.trend_explainer", "memory.reflector"]);
    expect(orderByDependencies([skillById("memory.reflector")!])[0]!.id).toBe("memory.reflector");
  });
});

describe("agent-fsm-v1", () => {
  test("16 keadaan; keadaan akhir tidak punya transisi; setiap keadaan non-akhir bisa gagal/batal", () => {
    expect(FSM_STATES.length).toBe(16);
    for (const s of FSM_STATES) {
      if (TERMINAL.has(s)) expect(TRANSITIONS[s]).toEqual([]);
      else expect(canTransition(s, "FAILED") && canTransition(s, "CANCELLED")).toBe(true);
    }
  });

  test("sifat: 2000 jalan acak tidak pernah keluar dari tabel dan tidak melampaui anggaran", () => {
    let seed = 7;
    const rnd = (n: number) => ((seed = (seed * 1103515245 + 12345) % 2 ** 31), seed % n);
    for (let run = 0; run < 2000; run++) {
      const m = createMachine({ maxIterations: 3, maxToolCalls: 8 }, () => 0);
      for (let step = 0; step < 40 && !TERMINAL.has(m.state); step++) {
        const target = FSM_STATES[rnd(FSM_STATES.length)] as FsmState;
        const legal = canTransition(m.state, target);
        if (target === "PLAN") m.beginIteration();
        if (target === "EXECUTE_READ_TOOLS" && m.remainingTools() > 0) m.useTool();
        try {
          m.to(target);
          expect(legal).toBe(true);
        } catch (e) {
          expect(e).toBeInstanceOf(FsmError);
          if (legal) expect((e as FsmError).code).toBe("ITERATION_BUDGET");
        }
        expect(m.iterations).toBeLessThanOrEqual(3);
        expect(m.toolCalls).toBeLessThanOrEqual(8);
      }
    }
  });

  test("anggaran alat dan iterasi ditegakkan; tindakan terotorisasi butuh kuitansi", () => {
    const m = createMachine({ maxToolCalls: 2 }, () => 0);
    m.useTool();
    m.useTool();
    expect(() => m.useTool()).toThrow(FsmError);
    expect(createMachine({ maxToolCalls: 99, maxIterations: 9 }).budget).toMatchObject({ maxToolCalls: 8, maxIterations: 3 });
    const w = createMachine({}, () => 0, "AWAIT_CONFIRMATION");
    expect(() => w.authorize(null)).toThrow("approval receipt");
    expect(() => createMachine({}, () => 0, "OUTPUT_GUARD").authorize({ operationId: "x", decision: "ACCEPT" })).toThrow(FsmError);
    w.authorize({ operationId: "op-1", decision: "ACCEPT" });
    expect(w.state).toBe("EXECUTE_AUTHORIZED_ACTION");
    const it = createMachine({}, () => 0, "EVALUATE_EVIDENCE");
    for (let i = 0; i < 3; i++) it.beginIteration();
    expect(it.beginIteration()).toBe(false);
    expect(() => it.to("PLAN")).toThrow("iteration budget");
    let t = 0;
    const late = createMachine({ deadlineMs: 10 }, () => t);
    t = 11;
    expect(() => late.useTool()).toThrow("deadline");
  });

  test("jalur turunan dari status run selalu legal", () => {
    for (const st of ["WAITING_FOR_USER", "COMPLETED", "BLOCKED", "FAILED"]) for (const usedTools of [true, false]) {
      const path = pathFor(st, { usedTools, offered: st === "WAITING_FOR_USER" });
      const m = createMachine({}, () => 0);
      for (const s of path.slice(1)) {
        if (s === "PLAN") m.beginIteration();
        m.to(s);
      }
      expect(m.state).toBe(path.at(-1)!);
    }
  });
});

describe("retrieval-v1 dan label kepastian", () => {
  test("label kepastian dari provenans", () => {
    expect(certaintyOf({ kind: "knowledge", reviewStatus: "REVIEWED" })).toBe("verified");
    expect(certaintyOf({ kind: "knowledge", reviewStatus: "DRAFT" })).toBe("insufficient");
    expect(certaintyOf({ kind: "food_reference", status: "verified_auto" })).toBe("verified");
    expect(certaintyOf({ kind: "web" })).toBe("estimated");
    expect(certaintyOf({ kind: "record", qualityStatus: "user_reported" })).toBe("reported");
    expect(certaintyOf({ kind: "record", qualityStatus: "device_reported" })).toBe("estimated");
    expect(certaintyOf({ kind: "device", status: "NO_DATA" })).toBe("insufficient");
    expect(certaintyOf({ kind: "projection", observedDays: 0, windowDays: 14 })).toBe("insufficient");
    expect(certaintyOf({ kind: "none" })).toBe("unknown");
  });

  test("normalisasi, potongan, sumber, RRF, penilaian cakupan", () => {
    expect(normalizeText("Pemeriksaan  RUTIN—penting!")).toBe("pemeriksaan rutin penting");
    const sec = chunkMarkdown("## A\nsatu\n- dua\n\n## Sumber\nADA 2026");
    expect(sec).toEqual([{ heading: "A", text: "satu dua" }, { heading: "Sumber", text: "ADA 2026" }]);
    expect(sourceOf(sec)).toBe("ADA 2026");
    expect(fuse([[{ id: "a", score: 1 }, { id: "b", score: 0.5 }], [{ id: "b", score: 0.9 }]])[0]!.id).toBe("b");
    expect(assessCoverage(null, { reviewedCount: 0, draftsAllowed: true }).status).toBe("ABSTAIN");
    expect(assessCoverage({ lexical: 0.1, vector: null }, { reviewedCount: 1, draftsAllowed: true }).reason).toBe("LOW_SCORE");
    expect(assessCoverage({ lexical: 0.8, vector: null }, { reviewedCount: 0, draftsAllowed: false }).reason).toBe("ONLY_UNREVIEWED_IN_PRODUCTION");
    expect(assessCoverage({ lexical: 0.8, vector: null }, { reviewedCount: 0, draftsAllowed: true }).status).toBe("ANSWER");
    expect(queryTerms("Bagaimana cara mencegah diabetes?")).toEqual(["mencegah", "diabetes"]);
    expect(lexicalScore(["mencegah", "diabetes"], normalizeText("Mencegah atau menunda diabetes tipe 2"))).toBe(1);
  });

  test("hambatan diklasifikasi tanpa model bahasa", () => {
    expect(classifyBarrier("aku sering lupa catat")).toBe("FORGOT");
    expect(classifyBarrier("nggak sempat, sibuk kerja")).toBe("TIME");
    expect(classifyBarrier("capek banget")).toBe("ENERGY");
    expect(classifyBarrier("aku susah konsisten")).toBe("MOTIVATION");
    expect(classifyBarrier("entahlah")).toBe("OTHER");
  });

  test("multi-intent: maksimal satu skill tambahan, keselamatan membatalkan pemecahan", () => {
    const body = "aku susah tidur dan aku malas olahraga";
    const primary = routeMessage(body, { hasPreviousRun: false });
    expect(primary.kind).toBe("SUPPORT");
    expect(secondaryRoutes(body, primary).map((r) => r.kind)).toEqual(["SLEEP"]);
    expect(routeMessage("pola tidurku gimana", { hasPreviousRun: false }).kind).toBe("SLEEP");
    expect(secondaryRoutes("berapa dosis insulin dan aku susah tidur", primary)).toEqual([]);
    expect(routeMessage("lagu yang enak buat tidur apa", { hasPreviousRun: false }).kind).toBe("UNKNOWN");
    expect(routeMessage("gimana cara mencegah diabetes", { hasPreviousRun: false }).kind).toBe("EDUCATION");
    expect(routeMessage("apakah saya kena prediabetes", { hasPreviousRun: false }).kind).toBe("SAFETY");
  });
});

describe("device-quality-v1", () => {
  const now = new Date("2026-11-10T05:00:00Z");
  const ctx = { today: "2026-11-10", now, connected: true, lastSyncAt: new Date("2026-11-10T04:00:00Z") };
  test("tanpa data tidak pernah disimpulkan tidak aktif", () => {
    const q = assessSteps("2026-11-05", [], ctx);
    expect(q).toMatchObject({ status: "NO_DATA", inference: "UNKNOWN", value: null });
    expect(assessSteps("2026-11-05", [], { ...ctx, connected: false }).status).toBe("NOT_CONNECTED");
    expect(assessSteps("2026-11-09", [], { ...ctx, lastSyncAt: new Date("2026-11-07T00:00:00Z") }).status).toBe("STALE");
  });
  test("hari berjalan PARTIAL, nilai tidak wajar, sinkron terlambat", () => {
    expect(assessSteps("2026-11-10", [{ localDate: "2026-11-10", steps: 3000, dataOrigin: "com.google.android.apps.fitness", syncedAt: now }], ctx)).toMatchObject({ status: "PARTIAL", inference: "OBSERVED" });
    expect(assessSteps("2026-11-08", [{ localDate: "2026-11-08", steps: 90_000, dataOrigin: null, syncedAt: now }], ctx).status).toBe("IMPLAUSIBLE");
    expect(assessSteps("2026-11-01", [{ localDate: "2026-11-01", steps: 5000, dataOrigin: null, syncedAt: now }], ctx).flags).toContain("LATE_SYNC");
  });
  test("tidur tumpang tindih dari dua asal = CONFLICT dengan nilai gabungan", () => {
    const rows = [
      { startedAt: new Date("2026-11-08T15:00:00Z"), endedAt: new Date("2026-11-08T22:00:00Z"), dataOrigin: "com.watch", createdAt: now, localDate: "2026-11-09" },
      { startedAt: new Date("2026-11-08T15:30:00Z"), endedAt: new Date("2026-11-08T22:30:00Z"), dataOrigin: "com.phone", createdAt: now, localDate: "2026-11-09" },
    ];
    expect(assessSleep("2026-11-09", rows, ctx)).toMatchObject({ status: "CONFLICT", value: 450, origins: ["com.phone", "com.watch"] });
    expect(assessSleep("2026-11-09", [rows[0]!], ctx)).toMatchObject({ status: "OK", value: 420 });
  });
  test("sesi latihan yang perlu ditinjau = CONFLICT dan tidak dihitung", () => {
    const w = assessWorkouts("2026-11-09", [{ startedAt: now, durationMinutes: 30, dataOrigin: "com.watch", receivedAt: now, qualityStatus: "needs_review", localDate: "2026-11-09" }, { startedAt: now, durationMinutes: 20, dataOrigin: "com.watch", receivedAt: now, qualityStatus: "device_reported", localDate: "2026-11-09" }], ctx);
    expect(w).toMatchObject({ status: "CONFLICT", value: 20 });
    const days = ["2026-11-07", "2026-11-08", "2026-11-09"].map((d) => assessSteps(d, d === "2026-11-08" ? [{ localDate: d, steps: 100, dataOrigin: null, syncedAt: now }] : [], ctx));
    expect(summarize("steps", days)).toMatchObject({ days: 3, observedDays: 1, coverage: 0.33, reliable: false });
    expect(addDays("2026-11-01", -1)).toBe("2026-10-31");
  });
});
