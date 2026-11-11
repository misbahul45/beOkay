import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const models: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const J = async (r: Response) => (await r.json()) as any;
afterAll(async () => {
  await prisma.users.deleteMany({ where: { id: { in: users } } });
  await prisma.mlInferenceRun.deleteMany({ where: { modelVersionId: { in: models } } });
  await prisma.modelVersion.deleteMany({ where: { id: { in: models } } });
});

async function userTables(): Promise<{ table: string; column: string }[]> {
  return prisma.$queryRaw<{ table: string; column: string }[]>`
    SELECT table_name AS "table", column_name AS "column" FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name IN ('user_id', 'userId') ORDER BY table_name`;
}

async function rowsFor(userId: string) {
  const out: Record<string, number> = {};
  for (const { table, column } of await userTables()) {
    const [r] = await prisma.$queryRawUnsafe<{ n: number }[]>(`SELECT count(*)::int AS n FROM "${table}" WHERE "${column}" = $1::uuid`, userId);
    if (r!.n > 0) out[table] = r!.n;
  }
  return out;
}

async function realUser() {
  const email = `del-${crypto.randomUUID()}@example.test`;
  const password = crypto.randomUUID();
  const signUp = await call("/api/auth/sign-up/email", undefined, { name: "Hapus", email, password });
  expect(signUp.status).toBe(200);
  const user = await prisma.users.update({ where: { email }, data: { emailVerified: true } });
  users.push(user.id);
  const signIn = await call("/api/auth/sign-in/email", undefined, { email, password });
  expect(signIn.status).toBe(200);
  const token = signIn.headers.get("set-auth-token")!;
  expect(token).toBeTruthy();
  return { id: user.id, token, password };
}

test("Hapus akun: kata sandi wajib, semua tabel milik pengguna bersih, akun lain utuh, sesi berakhir", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await realUser();
  const other = await realUser();

  const policy = await J(await call("/api/consent-policies/current", a.token));
  const purposes = ["health_data_processing", "descriptive_summaries", "personalized_ai", "community_membership", "challenge_participation"];
  for (const u of [a, other]) expect((await call("/api/me/consents", u.token, { policyVersion: policy.version, purposes, source: "api" })).status).toBe(200);

  const at = new Date(Date.now() - 3_600_000).toISOString();
  expect((await call("/api/me/glucose", a.token, { id: crypto.randomUUID(), originalValue: 120, originalUnit: "mg/dL", measuredAt: at })).status).toBe(201);
  expect((await call("/api/me/glucose", other.token, { id: crypto.randomUUID(), originalValue: 130, originalUnit: "mg/dL", measuredAt: at })).status).toBe(201);
  expect((await call("/api/me/activities", a.token, { id: crypto.randomUUID(), activityType: "walking", startedAt: at, durationMinutes: 20 })).status).toBe(201);
  const food = await J(await call("/api/me/foods", a.token, { name: "Nasi hapus", source: "fixture", status: "user_reported", per100g: { calories: 130, carbohydrates: 28, protein: 2, fat: 0.3, fiber: null } }));
  expect((await call("/api/me/meals", a.token, { id: crypto.randomUUID(), category: "lunch", consumedAt: at, items: [{ name: food.name, foodId: food.id, quantity: 150, unit: "g" }] })).status).toBe(201);
  expect((await call("/api/me/goals", a.token, { id: crypto.randomUUID(), title: "Jalan", goalType: "manual_checkins", targetValue: 3, period: "weekly", startDate: at.slice(0, 10) })).status).toBe(201);
  expect((await call("/api/me/reminders", a.token, { kind: "meal", title: "Makan", localTime: "12:00" })).status).toBe(201);
  expect((await call("/api/me/food-preferences", a.token, { kind: "allergy", term: "kacang" })).status).toBe(201);
  expect([200, 201]).toContain((await call("/api/me/push-devices", a.token, { token: `fcm-${crypto.randomUUID()}`, platform: "android" })).status);
  expect((await call("/api/me/interventions/evaluate", a.token, { trigger: "USER_REQUESTS_SUPPORT" })).status).toBe(200);
  const community = await prisma.community.findFirstOrThrow();
  expect([200, 201]).toContain((await call(`/api/me/communities/${community.id}/join`, a.token, { alias: `Hapus ${Math.floor(Math.random() * 9000 + 1000)}` })).status);
  const model = await prisma.modelVersion.create({ data: { modelKey: `del-test-${crypto.randomUUID()}`, version: "1", artifactSha256: "0".repeat(64), featureSchemaVersion: "1", status: "RESEARCH_ONLY", intendedUse: "test", trainingDataProvenance: "test", evaluation: {}, endpointRef: "test" } });
  models.push(model.id);
  const run = await prisma.mlInferenceRun.create({ data: { userId: a.id, modelVersionId: model.id, mode: "SHADOW", status: "OK", latencyMs: 1, inputBytes: 1 } });

  const before = await rowsFor(a.id);
  for (const t of ["glucose_observations", "activity_sessions", "meal_logs", "behavior_goals", "reminders", "food_preferences", "push_devices", "intervention_decisions", "community_memberships", "consent_records", "audit_events", "ml_inference_runs", "sessions", "accounts"]) {
    expect(before[t] ?? 0).toBeGreaterThan(0);
  }

  expect((await call("/api/auth/delete-user", a.token, {})).status).toBe(404);
  expect((await call("/api/me/account/delete", a.token, { password: a.password })).status).toBe(400);
  const wrong = await call("/api/me/account/delete", a.token, { password: "salah-sekali", confirm: "HAPUS" });
  expect(wrong.status).toBe(403);
  expect((await J(wrong)).error.code).toBe("INVALID_PASSWORD");
  expect(await prisma.users.count({ where: { id: a.id } })).toBe(1);

  const ok = await call("/api/me/account/delete", a.token, { password: a.password, confirm: "HAPUS" });
  expect(ok.status).toBe(200);
  expect(await J(ok)).toEqual({ deleted: true });

  expect(await prisma.users.count({ where: { id: a.id } })).toBe(0);
  expect(await rowsFor(a.id)).toEqual({});
  const orphan = await prisma.mlInferenceRun.findUniqueOrThrow({ where: { id: run.id } });
  expect(orphan.userId).toBeNull();
  expect(await prisma.auditEvent.count({ where: { userId: null, eventType: "account_deleted" } })).toBeGreaterThan(0);
  expect((await call("/api/me/profile", a.token)).status).toBe(401);

  const kept = await rowsFor(other.id);
  expect(kept.glucose_observations).toBe(1);
  expect((await call("/api/me/profile", other.token)).status).toBe(200);
});
