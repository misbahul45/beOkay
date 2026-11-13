import { logEvent } from "../../shared/http/logger.ts";
import { runSkill, RUNNABLE_SKILLS, type Block, type SkillResult } from "../agent/skills/runner.ts";
import { evaluateSkill, MAX_SKILLS_PER_MESSAGE, skillById, type Skill, type SelectionDenial } from "../agent/skills/registry.ts";
import { cohortService } from "../cohort/cohort.service.ts";
import { consentService } from "../consent/consent.service.ts";
import { featureFlags } from "../feature-flags/feature-flags.service.ts";
import type { Basis, BasisSource, Part } from "./conversation.parts.ts";
import { routeMessage, type Route } from "./conversation.router.ts";

export const ROUTE_SKILL: Partial<Record<Route["kind"], string>> = {
  FOOD: "nutrition.coach",
  CLARIFY_FOOD: "nutrition.coach",
  MEAL_LOG: "nutrition.coach",
  ACTIVITY_PLAN: "activity.planner",
  SLEEP: "sleep.recovery",
  SUPPORT: "behavior.barrier_solver",
  EDUCATION: "prevention.education",
  STATS: "health.trend_explainer",
  COMMUNITY: "social.challenge_coach",
  REFLECTION: "memory.reflector",
};

export function skillIdFor(route: Route, lastRoute?: string | null): string | null {
  if (route.kind === "FOLLOW_UP") return lastRoute === "ACTIVITY_PLAN" ? "activity.planner" : "nutrition.coach";
  return ROUTE_SKILL[route.kind] ?? null;
}

export type Gate = { skill: Skill | null; denial: SelectionDenial | null; journey: string | null };

export async function gateSkill(userId: string, route: Route, lastRoute?: string | null): Promise<Gate> {
  const id = skillIdFor(route, lastRoute);
  if (!id || !(await featureFlags.isEnabled("skill_registry"))) return { skill: null, denial: null, journey: null };
  const [journey, consents] = await Promise.all([cohortService.journeyOf(userId), consentService.activePurposes(userId)]);
  const skill = skillById(id);
  const denial = evaluateSkill(skill, id, { journey, consents, enabled: true });
  const enforced = denial && (denial.reason !== "CONSENT_REQUIRED" || RUNNABLE_SKILLS.has(id)) ? denial : null;
  logEvent("info", "skill_selection", { skill: id, journey, decision: enforced ? enforced.reason : "SELECTED" });
  return { skill, denial: enforced, journey };
}

export function denialParts(d: SelectionDenial): Part[] {
  if (d.reason === "CONSENT_REQUIRED") return [{ type: "consent_required", purpose: d.detail ?? "health_data_processing", text: "Fitur ini memerlukan persetujuanmu. Kamu bisa mengaturnya di Privasi & data." }];
  if (d.reason === "JOURNEY_NOT_ALLOWED" && d.skillId === "prevention.education") {
    return [{ type: "text", text: "Bacaan pencegahan ditujukan untuk jalur pencegahan dan gaya hidup sehat. Bacaan yang sesuai jalurmu ada di menu Edukasi." }];
  }
  if (d.reason === "JOURNEY_NOT_ALLOWED") {
    return [{ type: "text", text: "Fitur saran ini belum tersedia untuk keadaanmu. Kamu tetap bisa mencatat dan melihat catatanmu. Bila keadaanmu berubah, perbarui di Profil kesehatan." }, { type: "link", label: "Buka catatan", target: "LOG" }];
  }
  return [{ type: "text", text: "Fitur ini sedang tidak tersedia." }];
}

export function blocksToParts(blocks: Block[]): Part[] {
  const out: Part[] = [];
  for (const b of blocks) {
    if (b.type === "text") out.push({ type: "text", text: b.text });
    else if (b.type === "notice") out.push({ type: "notice", tone: b.tone, text: b.text });
    else if (b.type === "education") out.push({ type: "education", items: b.items });
    else if (b.type === "consent_required") out.push({ type: "consent_required", purpose: b.purpose, text: "Data perangkat untuk saran memerlukan persetujuanmu." });
    else out.push(b as unknown as Part);
  }
  return out;
}

export function basisOf(r: SkillResult): Basis & { certainty: string; skill: { id: string; runId: string; fsm: SkillResult["fsm"] } } {
  return { sources: r.sources as BasisSource[], memories: [], certainty: r.certainty, skill: { id: r.skillId, runId: r.runId, fsm: r.fsm } };
}

export async function runRouteSkill(userId: string, skill: Skill, text: string, clientMessageId: string, journey: string | null) {
  const j = (journey ?? (await cohortService.journeyOf(userId))) as Parameters<typeof runSkill>[0]["journey"];
  return runSkill({ userId, skill, text, idempotencyKey: `skill-${clientMessageId}-${skill.id}`, journey: j });
}

const SPLIT = /\s(?:dan juga|dan|lalu|terus|serta|plus|juga)\s/;
const SECONDARY_KINDS = new Set(["SLEEP", "SUPPORT", "EDUCATION"]);

export function secondaryRoutes(body: string, primary: Route): Route[] {
  const clauses = body.split(SPLIT).map((c) => c.trim()).filter((c) => c.split(" ").length >= 2);
  if (clauses.length < 2) return [];
  const out: Route[] = [];
  const seen = new Set<string>([primary.kind]);
  for (const c of clauses) {
    const r = routeMessage(c, { hasPreviousRun: false });
    if (r.kind === "SAFETY") return [];
    if (SECONDARY_KINDS.has(r.kind) && !seen.has(r.kind)) {
      seen.add(r.kind);
      out.push(r);
    }
  }
  return out.slice(0, MAX_SKILLS_PER_MESSAGE - 1);
}
