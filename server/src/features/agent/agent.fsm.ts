export const FSM_VERSION = "agent-fsm-v1";

export const FSM_STATES = [
  "RECEIVED",
  "SAFETY_SCREEN",
  "ROUTE",
  "SELECT_SKILL",
  "PLAN",
  "EXECUTE_READ_TOOLS",
  "EVALUATE_EVIDENCE",
  "DRAFT_RESPONSE",
  "OUTPUT_GUARD",
  "AWAIT_CONFIRMATION",
  "EXECUTE_AUTHORIZED_ACTION",
  "OBSERVE_OUTCOME",
  "COMPLETED",
  "BLOCKED",
  "FAILED",
  "CANCELLED",
] as const;
export type FsmState = (typeof FSM_STATES)[number];

export const TERMINAL: ReadonlySet<FsmState> = new Set(["COMPLETED", "BLOCKED", "FAILED", "CANCELLED"]);

export const TRANSITIONS: Readonly<Record<FsmState, readonly FsmState[]>> = {
  RECEIVED: ["SAFETY_SCREEN"],
  SAFETY_SCREEN: ["ROUTE", "BLOCKED"],
  ROUTE: ["SELECT_SKILL", "DRAFT_RESPONSE", "BLOCKED"],
  SELECT_SKILL: ["PLAN", "BLOCKED"],
  PLAN: ["EXECUTE_READ_TOOLS", "DRAFT_RESPONSE"],
  EXECUTE_READ_TOOLS: ["EVALUATE_EVIDENCE", "BLOCKED"],
  EVALUATE_EVIDENCE: ["PLAN", "DRAFT_RESPONSE"],
  DRAFT_RESPONSE: ["OUTPUT_GUARD"],
  OUTPUT_GUARD: ["COMPLETED", "AWAIT_CONFIRMATION", "DRAFT_RESPONSE", "BLOCKED"],
  AWAIT_CONFIRMATION: ["EXECUTE_AUTHORIZED_ACTION", "COMPLETED"],
  EXECUTE_AUTHORIZED_ACTION: ["OBSERVE_OUTCOME"],
  OBSERVE_OUTCOME: ["COMPLETED"],
  COMPLETED: [],
  BLOCKED: [],
  FAILED: [],
  CANCELLED: [],
};

export type Budget = { maxIterations: number; maxToolCalls: number; deadlineMs: number; maxGuardRetries: number };
export const DEFAULT_BUDGET: Budget = { maxIterations: 3, maxToolCalls: 8, deadlineMs: 20_000, maxGuardRetries: 1 };

export class FsmError extends Error {
  constructor(readonly code: "ILLEGAL_TRANSITION" | "TERMINAL_STATE" | "ITERATION_BUDGET" | "TOOL_BUDGET" | "DEADLINE" | "NO_RECEIPT", message: string) {
    super(message);
  }
}

export type Transition = { from: FsmState; to: FsmState; at: number; note?: string };

export function canTransition(from: FsmState, to: FsmState): boolean {
  if (TERMINAL.has(from)) return false;
  if (to === "FAILED" || to === "CANCELLED") return true;
  return TRANSITIONS[from].includes(to);
}

export type Machine = {
  readonly state: FsmState;
  readonly iterations: number;
  readonly toolCalls: number;
  readonly guardRetries: number;
  readonly history: readonly Transition[];
  readonly budget: Budget;
  to(next: FsmState, note?: string): void;
  beginIteration(): boolean;
  useTool(): void;
  retryGuard(): boolean;
  authorize(receipt: { operationId: string; decision: "ACCEPT" } | null): void;
  remainingTools(): number;
  expired(): boolean;
  annotate(note: string): void;
};

export function createMachine(budget: Partial<Budget> = {}, clock: () => number = Date.now, initial: FsmState = "RECEIVED"): Machine {
  const b: Budget = { ...DEFAULT_BUDGET, ...budget, maxIterations: Math.min(budget.maxIterations ?? DEFAULT_BUDGET.maxIterations, DEFAULT_BUDGET.maxIterations), maxToolCalls: Math.min(budget.maxToolCalls ?? DEFAULT_BUDGET.maxToolCalls, DEFAULT_BUDGET.maxToolCalls) };
  const started = clock();
  let state: FsmState = initial;
  let iterations = 0, toolCalls = 0, guardRetries = 0;
  const history: Transition[] = [];
  return {
    get state() { return state; },
    get iterations() { return iterations; },
    get toolCalls() { return toolCalls; },
    get guardRetries() { return guardRetries; },
    get history() { return history; },
    budget: b,
    to(next, note) {
      if (TERMINAL.has(state)) throw new FsmError("TERMINAL_STATE", `${state} is terminal`);
      if (!canTransition(state, next)) throw new FsmError("ILLEGAL_TRANSITION", `${state} -> ${next}`);
      if (next === "PLAN" && state === "EVALUATE_EVIDENCE" && iterations >= b.maxIterations) throw new FsmError("ITERATION_BUDGET", "iteration budget exhausted");
      history.push({ from: state, to: next, at: clock() - started, ...(note ? { note } : {}) });
      state = next;
    },
    beginIteration() {
      if (iterations >= b.maxIterations) return false;
      iterations++;
      return true;
    },
    useTool() {
      if (toolCalls >= b.maxToolCalls) throw new FsmError("TOOL_BUDGET", "tool budget exhausted");
      if (clock() - started > b.deadlineMs) throw new FsmError("DEADLINE", "run deadline passed");
      toolCalls++;
    },
    retryGuard() {
      if (guardRetries >= b.maxGuardRetries) return false;
      guardRetries++;
      return true;
    },
    authorize(receipt) {
      if (state !== "AWAIT_CONFIRMATION") throw new FsmError("ILLEGAL_TRANSITION", `${state} -> EXECUTE_AUTHORIZED_ACTION`);
      if (!receipt || receipt.decision !== "ACCEPT" || !receipt.operationId) throw new FsmError("NO_RECEIPT", "authorized action requires an approval receipt");
      this.to("EXECUTE_AUTHORIZED_ACTION", `receipt:${receipt.operationId}`);
    },
    remainingTools() {
      return b.maxToolCalls - toolCalls;
    },
    expired() {
      return clock() - started > b.deadlineMs;
    },
    annotate(note) {
      const last = history.at(-1);
      if (last) last.note = last.note ? `${last.note};${note}` : note;
    },
  };
}

export const RUN_STATUS_TO_FSM: Record<string, FsmState> = {
  CREATED: "RECEIVED",
  VALIDATING: "SAFETY_SCREEN",
  RUNNING: "EXECUTE_READ_TOOLS",
  WAITING_FOR_USER: "AWAIT_CONFIRMATION",
  COMPLETED: "COMPLETED",
  BLOCKED: "BLOCKED",
  FAILED: "FAILED",
  EXPIRED: "CANCELLED",
  CANCELLED: "CANCELLED",
};

export function pathFor(finalStatus: string, opts: { usedTools: boolean; offered: boolean }): FsmState[] {
  const head: FsmState[] = ["RECEIVED", "SAFETY_SCREEN"];
  if (finalStatus === "BLOCKED") return [...head, "BLOCKED"];
  const mid: FsmState[] = ["ROUTE", "SELECT_SKILL", "PLAN", ...(opts.usedTools ? (["EXECUTE_READ_TOOLS", "EVALUATE_EVIDENCE"] as FsmState[]) : []), "DRAFT_RESPONSE", "OUTPUT_GUARD"];
  if (finalStatus === "FAILED") return [...head, "ROUTE", "SELECT_SKILL", "PLAN", "FAILED"];
  if (finalStatus === "WAITING_FOR_USER" || opts.offered) return [...head, ...mid, "AWAIT_CONFIRMATION"];
  return [...head, ...mid, "COMPLETED"];
}
