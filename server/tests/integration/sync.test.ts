import { afterAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
async function actor() {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "Fixture", email: `sync-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes: ["health_data_processing", "descriptive_summaries"] });
  await call("/api/me/preferences", token, { timezone: "Asia/Jakarta" }, "PATCH");
  return { id, token };
}
afterAll(async () => { await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const J = async (r: Response) => (await r.json()) as any;
const sync = (token: string | undefined, operations: object[]) => call("/api/me/sync/operations", token, { operations });
const glucose = (recordId: string, value = 110) => ({
  operationId: crypto.randomUUID(), domain: "glucose", recordId, operationType: "create",
  payload: { originalValue: value, originalUnit: "mg/dL", measuredAt: new Date(Date.now() - 60000).toISOString() },
});

test("Sync: idempotent retry, conflicts, validation, isolation, consent withdrawal", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const a = await actor(), b = await actor();
  expect((await sync(undefined, [glucose(crypto.randomUUID())])).status).toBe(401);
  expect((await sync(a.token, [])).status).toBe(400);

  // Create + retry with same operationId returns the stored result, no duplicate row.
  const rec = crypto.randomUUID();
  const op = glucose(rec);
  let res = await J(await sync(a.token, [op]));
  expect(res.items[0]).toMatchObject({ operationId: op.operationId, status: "SYNCED", recordId: rec });
  expect(res.items[0].result.version).toBe(1);
  res = await J(await sync(a.token, [op]));
  expect(res.items[0]).toMatchObject({ status: "SYNCED", recordId: rec });
  expect(await prisma.glucoseObservation.count({ where: { id: rec } })).toBe(1);

  // Same operationId, different payload -> conflict, original untouched.
  res = await J(await sync(a.token, [{ ...op, payload: { ...op.payload, originalValue: 200 } }]));
  expect(res.items[0]).toMatchObject({ status: "CONFLICT", error: { code: "OPERATION_ID_REUSED" } });

  // Update with correct then stale version.
  const upd = (version: number, v: number) => ({
    operationId: crypto.randomUUID(), domain: "glucose", recordId: rec, operationType: "update",
    payload: { originalValue: v, expectedVersion: version, reason: "Koreksi dari antrean offline" },
  });
  res = await J(await sync(a.token, [upd(1, 120)]));
  expect(res.items[0]).toMatchObject({ status: "SYNCED" });
  expect(res.items[0].result.version).toBe(2);
  res = await J(await sync(a.token, [upd(1, 130)]));
  expect(res.items[0]).toMatchObject({ status: "CONFLICT", error: { code: "VERSION_CONFLICT" } });

  // Per-operation processing: invalid item does not block valid ones.
  const bad = { ...glucose(crypto.randomUUID()), payload: { originalValue: -5, originalUnit: "mg/dL", measuredAt: new Date().toISOString() } };
  const good = glucose(crypto.randomUUID(), 95);
  res = await J(await sync(a.token, [bad, good]));
  expect(res.items.map((i: any) => i.status)).toEqual(["NEEDS_REVIEW", "SYNCED"]);

  // Medication intake needs a parent; goal check-in dispatches to the goals service.
  const noParent = { operationId: crypto.randomUUID(), domain: "medication_intake", recordId: crypto.randomUUID(), operationType: "create", payload: { status: "taken" } };
  res = await J(await sync(a.token, [noParent]));
  expect(res.items[0].status).toBe("NEEDS_REVIEW");
  const regimen = { id: crypto.randomUUID(), name: "Obat uji sintetis", strength: "500 mg", dosageForm: "tablet", dosingInstructions: "Sesuai laporan pengguna" };
  expect((await call("/api/me/medications", a.token, regimen)).status).toBe(201);
  const intake = { operationId: crypto.randomUUID(), domain: "medication_intake", recordId: crypto.randomUUID(), parentId: regimen.id, operationType: "create", payload: { status: "taken", takenAt: new Date(Date.now() - 60000).toISOString() } };
  res = await J(await sync(a.token, [intake]));
  expect(res.items[0]).toMatchObject({ status: "SYNCED" });

  // Isolation: B cannot write into A's regimen or touch A's record, and receipts are per user.
  res = await J(await sync(b.token, [{ ...intake, operationId: crypto.randomUUID(), recordId: crypto.randomUUID() }]));
  expect(res.items[0].status).toBe("NEEDS_REVIEW"); // regimen not found for B
  res = await J(await sync(b.token, [{ ...upd(2, 140), operationId: crypto.randomUUID() }]));
  expect(res.items[0].status).not.toBe("SYNCED");
  expect((await prisma.glucoseObservation.findUnique({ where: { id: rec } }))?.version).toBe(2);
  res = await J(await sync(b.token, [op])); // A's operationId under B's token is B's own new operation
  expect(res.items[0].status).not.toBe("SYNCED"); // recordId already belongs to A -> idempotency conflict, not rebinding
  expect((await prisma.glucoseObservation.findUnique({ where: { id: rec } }))?.userId).toBe(a.id);
  const sa = await J(await call("/api/me/sync/status", a.token));
  const sb = await J(await call("/api/me/sync/status", b.token));
  expect(sa.items.length).toBeGreaterThan(0);
  expect(sa.items.every((i: any) => !("payload" in i) && !("result" in i))).toBe(true);
  expect(sb.items.some((i: any) => i.operationId === intake.operationId)).toBe(false);

  // Weekly cross-domain summary: derived, persisted as a projection, marked STALE by later writes.
  const weekly = await J(await call("/api/me/summaries/weekly", a.token));
  expect(weekly.days).toHaveLength(7);
  expect(weekly).toMatchObject({ freshness: "CURRENT", analyticsState: "READY" });
  expect(weekly.glucose.total).toBeGreaterThanOrEqual(2);
  expect(weekly.medication.scheduled).toBe(0);
  expect((await prisma.summaryProjection.findFirst({ where: { userId: a.id, kind: "weekly" } }))?.freshnessStatus).toBe("CURRENT");
  await sync(a.token, [glucose(crypto.randomUUID(), 101)]);
  expect((await prisma.summaryProjection.findFirst({ where: { userId: a.id, kind: "weekly" } }))?.freshnessStatus).toBe("STALE");
  expect((await call("/api/me/summaries/weekly", b.token)).status).toBe(200);
  expect((await call("/api/me/summaries/weekly")).status).toBe(401);

  // Consent withdrawal stops sync entirely; data remains inaccessible until re-granted.
  const w = await call("/api/me/consents/withdraw", a.token, { purposes: ["health_data_processing"] });
  expect(w.status).toBe(200);
  expect((await sync(a.token, [glucose(crypto.randomUUID())])).status).toBe(403);
  expect((await call("/api/me/glucose", a.token)).status).toBe(403);
});
