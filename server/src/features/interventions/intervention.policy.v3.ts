import { classify, decide, USER_INITIATED, type PolicyInput, type PolicyResult } from "./intervention.policy.ts";

export const INTERVENTION_POLICY_V3 = "jitai-policy-v3";

export type DecisionV3 = "INTERVENE" | "DEFER" | "ASK_FOR_CLARIFICATION" | "WITHHOLD" | "NO_INTERVENTION";
export type WithholdReason = "SAFETY_HOLD" | "USER_UNWELL" | "LOW_ENERGY_REPORTED" | "DATA_UNRELIABLE" | "REQUIRES_REVIEW";

export type V3Signals = {
  safetyHold: boolean;
  unwell: boolean;
  energy: "LOW" | "OK" | "HIGH" | null;
  dataDependent: boolean;
  dataReliable: boolean | null;
};

export type V3Result = PolicyResult & { decision: DecisionV3; withhold: WithholdReason | null; base: PolicyResult; policyVersion: string };

const withhold = (base: PolicyResult, reason: WithholdReason): V3Result => ({ option: "NO_INTERVENTION", reason: `WITHHOLD:${reason}`, coverage: base.coverage, decision: "WITHHOLD", withhold: reason, base, policyVersion: INTERVENTION_POLICY_V3 });

export function decideV3(input: PolicyInput, s: V3Signals): V3Result {
  const base = decide(input);
  const userInitiated = USER_INITIATED.has(input.trigger);
  if (!input.consent) return { ...base, decision: "NO_INTERVENTION", withhold: null, base, policyVersion: INTERVENTION_POLICY_V3 };
  if (s.safetyHold) return withhold(base, "SAFETY_HOLD");
  if (base.reason === "REQUIRES_REVIEW") return { ...base, decision: "WITHHOLD", withhold: "REQUIRES_REVIEW", base, policyVersion: INTERVENTION_POLICY_V3 };
  if (!userInitiated && s.unwell) return withhold(base, "USER_UNWELL");
  if (!userInitiated && s.energy === "LOW" && input.trigger === "COACHING_ACTION_DUE") return withhold(base, "LOW_ENERGY_REPORTED");
  if (s.dataDependent && s.dataReliable === false && base.option !== "NO_INTERVENTION") return withhold(base, "DATA_UNRELIABLE");
  const c = classify(base);
  const decision: DecisionV3 = c === "INTERVENE" ? "INTERVENE" : c === "DEFER" ? "DEFER" : c === "ASK_FOR_CLARIFICATION" ? "ASK_FOR_CLARIFICATION" : c === "REQUIRES_REVIEW" ? "WITHHOLD" : "NO_INTERVENTION";
  return { ...base, decision, withhold: null, base, policyVersion: INTERVENTION_POLICY_V3 };
}

export function classifyStored(option: string, reason: string | null): DecisionV3 {
  if (reason?.startsWith("WITHHOLD:")) return "WITHHOLD";
  const c = classify({ option: option as PolicyResult["option"], reason });
  return c === "DO_NOT_INTERVENE" ? "NO_INTERVENTION" : c === "REQUIRES_REVIEW" ? "WITHHOLD" : c;
}
