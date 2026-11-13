import type { ConsentPurpose } from "../../consent/consent.policy.ts";
import type { Journey } from "../../cohort/cohort.policy.ts";

export const SKILL_REGISTRY_VERSION = "skills-v1";

export type ToolTier = "READ_ONLY" | "USER_CONFIRMED" | "PROHIBITED";
export type EvidenceLane = "A_PUBLIC_HEALTH" | "B_FOOD_REFERENCE" | "C_BEHAVIOR_STRATEGY" | "D_PERSONAL_RECORDS" | "E_PERSONAL_MEMORY";
export type SkillStatus = "ACTIVE" | "SHADOW" | "DISABLED";
export type MemoryAccess = "NONE" | "READ" | "READ_PROPOSE";

export const SKILL_ROUTES = ["FOOD", "CLARIFY_FOOD", "MEAL_LOG", "ACTIVITY_PLAN", "SLEEP", "SUPPORT", "EDUCATION", "STATS", "COMMUNITY", "REFLECTION"] as const;
export type SkillRoute = (typeof SKILL_ROUTES)[number];

export type Skill = {
  id: string;
  version: string;
  title: string;
  purpose: string;
  routes: readonly SkillRoute[];
  intent: string;
  allowedJourneys: readonly Journey[];
  requiredConsents: readonly ConsentPurpose[];
  optionalConsents: readonly ConsentPurpose[];
  allowedTools: readonly string[];
  confirmedActions: readonly string[];
  prohibitedActions: readonly string[];
  evidenceLanes: readonly EvidenceLane[];
  memoryAccess: MemoryAccess;
  outputSchema: string;
  safetyLevel: "STANDARD" | "ELEVATED";
  maxIterations: number;
  maxToolCalls: number;
  timeoutMs: number;
  after: readonly string[];
  status: SkillStatus;
  owner: string;
  contentReview: "NOT_REQUIRED" | "DRAFT_NOT_CLINICALLY_REVIEWED" | "REVIEWED";
};

export const GLOBAL_PROHIBITED = [
  "diagnose_condition",
  "change_medication",
  "set_insulin_dose",
  "prescribe_exercise_volume",
  "set_weight_target",
  "interpret_lab_result",
  "send_external_message",
  "read_other_user",
  "raw_query",
  "write_health_record",
] as const;

const ACTIVE: readonly Journey[] = ["PREVENTION", "T2DM_SUPPORT", "WELLNESS"];
const base = {
  version: "1",
  prohibitedActions: GLOBAL_PROHIBITED,
  safetyLevel: "STANDARD" as const,
  maxIterations: 3,
  maxToolCalls: 8,
  timeoutMs: 20_000,
  after: [] as string[],
  status: "ACTIVE" as const,
  owner: "beokay-core",
  optionalConsents: [] as ConsentPurpose[],
  confirmedActions: [] as string[],
};

export const SKILLS: readonly Skill[] = [
  {
    ...base,
    id: "nutrition.coach",
    title: "Pilihan makan",
    purpose: "Info gizi bersumber dan alternatif makanan sesuai preferensi; mencatat makan hanya dari draf yang dikonfirmasi.",
    routes: ["FOOD", "CLARIFY_FOOD", "MEAL_LOG"],
    intent: "NUTRITION_ALTERNATIVES",
    allowedJourneys: ACTIVE,
    requiredConsents: ["health_data_processing"],
    optionalConsents: ["personalized_ai", "ai_text_generation"],
    allowedTools: ["get_food_preferences", "get_personalization", "search_food_reference", "search_user_foods", "search_web_nutrition", "get_memory_context"],
    confirmedActions: ["plan_meal", "save_food_preference", "save_memory"],
    evidenceLanes: ["B_FOOD_REFERENCE", "D_PERSONAL_RECORDS", "E_PERSONAL_MEMORY"],
    memoryAccess: "READ_PROPOSE",
    outputSchema: "recommendations.food.v1",
    contentReview: "NOT_REQUIRED",
  },
  {
    ...base,
    id: "activity.planner",
    title: "Rencana gerak kecil",
    purpose: "Usulan aktivitas ringan sesuai riwayat, waktu luang, dan ingatan; tidak menaikkan intensitas.",
    routes: ["ACTIVITY_PLAN"],
    intent: "ACTIVITY_PLAN",
    allowedJourneys: ACTIVE,
    requiredConsents: ["health_data_processing"],
    optionalConsents: ["personalized_ai", "device_data_coaching"],
    allowedTools: ["get_activity_context", "get_behavior_goals", "get_personalization", "get_daily_facts", "get_memory_context"],
    confirmedActions: ["plan_activity", "save_memory"],
    evidenceLanes: ["C_BEHAVIOR_STRATEGY", "D_PERSONAL_RECORDS", "E_PERSONAL_MEMORY"],
    memoryAccess: "READ_PROPOSE",
    outputSchema: "recommendations.activity.v1",
    safetyLevel: "ELEVATED",
    contentReview: "DRAFT_NOT_CLINICALLY_REVIEWED",
  },
  {
    ...base,
    id: "sleep.recovery",
    title: "Tidur dan pulih",
    purpose: "Menjelaskan pola tidur tercatat dan kualitas datanya, ditambah bacaan umum; tanpa penilaian klinis.",
    routes: ["SLEEP"],
    intent: "SLEEP_RECOVERY",
    allowedJourneys: ACTIVE,
    requiredConsents: ["health_data_processing", "descriptive_summaries"],
    optionalConsents: ["device_data_coaching"],
    allowedTools: ["get_daily_facts", "get_device_quality", "search_knowledge"],
    evidenceLanes: ["A_PUBLIC_HEALTH", "D_PERSONAL_RECORDS"],
    memoryAccess: "NONE",
    outputSchema: "explanation.sleep.v1",
    contentReview: "DRAFT_NOT_CLINICALLY_REVIEWED",
  },
  {
    ...base,
    id: "behavior.barrier_solver",
    title: "Mengatasi hambatan",
    purpose: "Memilih satu strategi perilaku dari katalog untuk hambatan yang diceritakan pengguna.",
    routes: ["SUPPORT"],
    intent: "BARRIER_SOLVING",
    allowedJourneys: ACTIVE,
    requiredConsents: ["health_data_processing"],
    optionalConsents: ["personalized_ai"],
    allowedTools: ["get_memory_context", "search_knowledge", "get_behavior_goals"],
    confirmedActions: ["save_memory"],
    evidenceLanes: ["C_BEHAVIOR_STRATEGY", "E_PERSONAL_MEMORY"],
    memoryAccess: "READ_PROPOSE",
    outputSchema: "strategy.barrier.v1",
    contentReview: "DRAFT_NOT_CLINICALLY_REVIEWED",
  },
  {
    ...base,
    id: "prevention.education",
    title: "Bacaan pencegahan",
    purpose: "Bacaan umum tentang pencegahan dan pemeriksaan rutin; abstain bila tidak ada bacaan yang cocok.",
    routes: ["EDUCATION"],
    intent: "PREVENTION_EDUCATION",
    allowedJourneys: ["PREVENTION", "WELLNESS"],
    requiredConsents: ["health_data_processing"],
    allowedTools: ["search_knowledge"],
    evidenceLanes: ["A_PUBLIC_HEALTH"],
    memoryAccess: "NONE",
    outputSchema: "education.answer.v1",
    safetyLevel: "ELEVATED",
    contentReview: "DRAFT_NOT_CLINICALLY_REVIEWED",
  },
  {
    ...base,
    id: "health.trend_explainer",
    title: "Penjelas tren",
    purpose: "Ringkasan deskriptif catatan sendiri; tanpa sebab-akibat dan tanpa prediksi.",
    routes: ["STATS"],
    intent: "TREND_EXPLAIN",
    allowedJourneys: ACTIVE,
    requiredConsents: ["health_data_processing", "descriptive_summaries"],
    allowedTools: ["get_daily_facts", "get_device_quality"],
    evidenceLanes: ["D_PERSONAL_RECORDS"],
    memoryAccess: "NONE",
    outputSchema: "statistics.v1",
    contentReview: "NOT_REQUIRED",
  },
  {
    ...base,
    id: "social.challenge_coach",
    title: "Tantangan",
    purpose: "Menjelaskan aturan, progres, dan tantangan terbuka; bergabung hanya lewat konfirmasi di halaman tantangan.",
    routes: ["COMMUNITY"],
    intent: "CHALLENGE_COACH",
    allowedJourneys: ACTIVE,
    requiredConsents: ["health_data_processing"],
    optionalConsents: ["community_membership", "challenge_participation", "social_outcomes_memory"],
    allowedTools: ["get_daily_facts"],
    confirmedActions: ["join_challenge"],
    evidenceLanes: ["D_PERSONAL_RECORDS"],
    memoryAccess: "NONE",
    outputSchema: "challenges.v1",
    contentReview: "NOT_REQUIRED",
  },
  {
    ...base,
    id: "memory.reflector",
    title: "Refleksi",
    purpose: "Refleksi mingguan dari catatan dan rencana; perubahan target hanya atas persetujuan.",
    routes: ["REFLECTION"],
    intent: "MEMORY_REFLECT",
    allowedJourneys: ACTIVE,
    requiredConsents: ["health_data_processing"],
    optionalConsents: ["descriptive_summaries", "personalized_ai", "social_outcomes_memory"],
    allowedTools: ["get_daily_facts", "get_memory_context", "get_behavior_goals"],
    confirmedActions: ["adjust_goal", "save_memory"],
    evidenceLanes: ["D_PERSONAL_RECORDS", "E_PERSONAL_MEMORY"],
    memoryAccess: "READ_PROPOSE",
    outputSchema: "reflection.v1",
    after: ["health.trend_explainer"],
    contentReview: "NOT_REQUIRED",
  },
];

const byId = new Map(SKILLS.map((s) => [s.id, s]));
export const skillById = (id: string) => byId.get(id) ?? null;
export const skillForRoute = (route: string) => SKILLS.find((s) => (s.routes as readonly string[]).includes(route)) ?? null;

export type SelectionDenial = { skillId: string; reason: "UNKNOWN_SKILL" | "SKILL_DISABLED" | "JOURNEY_NOT_ALLOWED" | "CONSENT_REQUIRED"; detail?: string };
export type SelectionContext = { journey: Journey; consents: ReadonlySet<string>; enabled: boolean };
export type Selection = { skills: Skill[]; denied: SelectionDenial[]; registryVersion: string };

export function evaluateSkill(skill: Skill | null, id: string, ctx: SelectionContext): SelectionDenial | null {
  if (!skill) return { skillId: id, reason: "UNKNOWN_SKILL" };
  if (skill.status === "DISABLED") return { skillId: id, reason: "SKILL_DISABLED" };
  if (!skill.allowedJourneys.includes(ctx.journey)) return { skillId: id, reason: "JOURNEY_NOT_ALLOWED", detail: ctx.journey };
  const missing = skill.requiredConsents.find((p) => !ctx.consents.has(p));
  if (missing) return { skillId: id, reason: "CONSENT_REQUIRED", detail: missing };
  return null;
}

export function orderByDependencies(skills: Skill[]): Skill[] {
  const ids = new Set(skills.map((s) => s.id));
  const out: Skill[] = [];
  const seen = new Set<string>();
  const visit = (s: Skill, stack: Set<string>) => {
    if (seen.has(s.id)) return;
    if (stack.has(s.id)) throw new Error(`SKILL_DEPENDENCY_CYCLE:${s.id}`);
    stack.add(s.id);
    for (const dep of s.after) if (ids.has(dep)) visit(byId.get(dep)!, stack);
    stack.delete(s.id);
    seen.add(s.id);
    out.push(s);
  };
  for (const s of skills) visit(s, new Set());
  return out;
}

export const MAX_SKILLS_PER_MESSAGE = 2;

export function selectSkills(requested: readonly string[], ctx: SelectionContext): Selection {
  const denied: SelectionDenial[] = [];
  const chosen: Skill[] = [];
  for (const id of [...new Set(requested)].slice(0, MAX_SKILLS_PER_MESSAGE)) {
    const skill = skillById(id);
    const denial = evaluateSkill(skill, id, ctx);
    if (denial) denied.push(denial);
    else chosen.push(skill!);
  }
  return { skills: orderByDependencies(chosen), denied, registryVersion: SKILL_REGISTRY_VERSION };
}

export function validateRegistry(skills: readonly Skill[] = SKILLS, knownTools: ReadonlySet<string>): string[] {
  const problems: string[] = [];
  const ids = new Set<string>();
  const routes = new Map<string, string>();
  for (const s of skills) {
    if (ids.has(s.id)) problems.push(`DUPLICATE_ID:${s.id}`);
    ids.add(s.id);
    if (!/^[a-z]+\.[a-z_]+$/.test(s.id)) problems.push(`BAD_ID:${s.id}`);
    if (s.maxIterations < 1 || s.maxIterations > 3) problems.push(`ITERATIONS_OUT_OF_RANGE:${s.id}`);
    if (s.maxToolCalls < 1 || s.maxToolCalls > 8) problems.push(`TOOL_BUDGET_OUT_OF_RANGE:${s.id}`);
    if (!s.allowedJourneys.length) problems.push(`NO_JOURNEY:${s.id}`);
    if (s.allowedJourneys.includes("UNDETERMINED")) problems.push(`UNDETERMINED_NOT_ALLOWED:${s.id}`);
    if (!s.requiredConsents.includes("health_data_processing")) problems.push(`MISSING_BASE_CONSENT:${s.id}`);
    for (const t of s.allowedTools) if (!knownTools.has(t)) problems.push(`UNKNOWN_TOOL:${s.id}:${t}`);
    for (const t of s.allowedTools) if ((GLOBAL_PROHIBITED as readonly string[]).includes(t)) problems.push(`PROHIBITED_TOOL:${s.id}:${t}`);
    for (const p of GLOBAL_PROHIBITED) if (!s.prohibitedActions.includes(p)) problems.push(`PROHIBITION_MISSING:${s.id}:${p}`);
    for (const r of s.routes) {
      if (routes.has(r)) problems.push(`ROUTE_CLAIMED_TWICE:${r}`);
      routes.set(r, s.id);
    }
    for (const d of s.after) if (!skills.some((o) => o.id === d)) problems.push(`UNKNOWN_DEPENDENCY:${s.id}:${d}`);
  }
  return problems;
}
