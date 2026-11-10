import { afterAll, beforeAll, expect, test } from "bun:test";
import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { createDishService } from "../../src/features/ml/dish.service.ts";
import { createModalClient } from "../../src/features/ml/modal.client.ts";

const api = process.env.API_BASE_URL;
const users: string[] = [];
const call = (path: string, token?: string, body?: object, method = body ? "POST" : "GET") =>
  fetch(api + path, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
const SHA = "b".repeat(64), KEY = "dish-classifier";
async function actor(purposes: string[]) {
  const id = crypto.randomUUID(), token = crypto.randomUUID();
  users.push(id);
  await prisma.users.create({ data: { id, name: "F", email: `ml-${id}@example.test`, emailVerified: true, createdAt: new Date(), updatedAt: new Date() } });
  await prisma.sessions.create({ data: { id: crypto.randomUUID(), userId: id, token, createdAt: new Date(), updatedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
  const policy = (await (await call("/api/consent-policies/current", token)).json()) as any;
  await call("/api/me/consents", token, { policyVersion: policy.version, purposes });
  return { id, token };
}
const reply = (over: object = {}) => Response.json({ modelKey: KEY, modelVersion: "vtest", artifactSha256: SHA, predictions: [{ label: "Rendang", probability: 0.9 }, { label: "Soto", probability: 0.05 }], ...over });
const svc = (resp: () => Response | Promise<Response>) => {
  let calls = 0;
  const s = createDishService(createModalClient({ url: "https://beokay--x.modal.run", token: "t" }, { fetchImpl: (async () => { calls++; return resp(); }) as unknown as typeof fetch }));
  return { s, calls: () => calls };
};
beforeAll(async () => { await prisma.modelVersion.deleteMany({ where: { modelKey: KEY } }); });
afterAll(async () => { await prisma.mlInferenceRun.deleteMany({ where: { model: { modelKey: KEY } } }); await prisma.modelVersion.deleteMany({ where: { modelKey: KEY } }); await prisma.users.deleteMany({ where: { id: { in: users } } }); });
const register = (status: string, over: object = {}) => prisma.modelVersion.create({ data: { modelKey: KEY, version: "vtest", artifactSha256: SHA, featureSchemaVersion: "img224-v1", status, intendedUse: "Kandidat nama hidangan (bukan kalori/porsi)", trainingDataProvenance: "Kaggle rizkyyk/dataset-food-classification; lisensi tidak tercantum", evaluation: { accuracy: 0.9 }, endpointRef: "modal:beokay-dish", ...over } });

test("Tanpa model terdaftar: bayangan tidak berjalan dan tidak memanggil Modal", async () => {
  if (!api || process.env.NODE_ENV !== "test") throw new Error("Isolated API required");
  const u = await actor(["health_data_processing", "model_inference"]);
  const { s, calls } = svc(() => reply());
  expect(await s.shadow(u.id, new Uint8Array([1]))).toEqual({ ran: false, reason: "NO_MODEL" });
  expect(calls()).toBe(0);
  expect(await s.liveRecommendation(new Uint8Array([1]))).toBeNull();
});

test("RESEARCH_ONLY: hanya mode bayangan, butuh consent model_inference, dicatat tanpa gambar; tidak pernah dikembalikan ke pengguna", async () => {
  const consenting = await actor(["health_data_processing", "model_inference"]);
  const refusing = await actor(["health_data_processing"]);
  await register("RESEARCH_ONLY");
  const { s, calls } = svc(() => reply());

  expect(await s.shadow(refusing.id, new Uint8Array([1, 2, 3]))).toEqual({ ran: false, reason: "NO_CONSENT" });
  expect(calls()).toBe(0); // tanpa persetujuan, foto tidak dikirim
  expect(await prisma.mlInferenceRun.count({ where: { userId: refusing.id } })).toBe(0);

  expect(await s.shadow(consenting.id, new Uint8Array([1, 2, 3]))).toEqual({ ran: true });
  const run = await prisma.mlInferenceRun.findFirstOrThrow({ where: { userId: consenting.id } });
  expect(run).toMatchObject({ mode: "SHADOW", status: "OK", inputBytes: 3, topLabel: "Rendang" });
  expect(Object.keys(run).sort()).toEqual(["createdAt", "id", "inputBytes", "latencyMs", "mode", "modelVersionId", "status", "topLabel", "topProbability", "userId"]); // tidak ada kolom gambar
  // Model riset TIDAK dipakai untuk hasil pengguna.
  expect(await s.liveRecommendation(new Uint8Array([1]))).toBeNull();
  const cap = await s.capabilities();
  expect(cap.models.find((m) => m.version === "vtest")).toMatchObject({ status: "RESEARCH_ONLY", usableForUsers: false });
});

test("Versi/hash artefak yang menjawab harus cocok dengan registri; kegagalan Modal dicatat dan tidak melempar", async () => {
  const u = await actor(["health_data_processing", "model_inference"]);
  const mismatch = svc(() => reply({ artifactSha256: "c".repeat(64) }));
  expect(await mismatch.s.shadow(u.id, new Uint8Array([1]))).toEqual({ ran: true, reason: "VERSION_MISMATCH" });
  const down = svc(() => new Response("x", { status: 503 }));
  expect(await down.s.shadow(u.id, new Uint8Array([1]))).toEqual({ ran: true, reason: "UNAVAILABLE" });
  const statuses = (await prisma.mlInferenceRun.findMany({ where: { userId: u.id }, orderBy: { createdAt: "asc" } })).map((r) => r.status);
  expect(statuses).toEqual(["VERSION_MISMATCH", "UNAVAILABLE"]);
  // Tidak dikonfigurasi: tidak ada jaringan, tidak ada galat.
  const none = createDishService(createModalClient({ url: undefined, token: undefined }));
  expect(await none.shadow(u.id, new Uint8Array([1]))).toEqual({ ran: false, reason: "NOT_CONFIGURED" });
});

test("Hanya model APPROVED yang menghasilkan rekomendasi live; DEPRECATED diabaikan", async () => {
  await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data: { status: "APPROVED", approvedAt: new Date(), approvalNote: "Disetujui pemilik untuk uji otomatis (fixture)." } });
  const { s } = svc(() => reply());
  expect(await s.liveRecommendation(new Uint8Array([1]))).toMatchObject({ modelVersion: "vtest", predictions: [{ label: "Rendang" }, { label: "Soto" }] });
  const bad = svc(() => reply({ modelVersion: "lain" }));
  expect(await bad.s.liveRecommendation(new Uint8Array([1]))).toBeNull(); // versi tidak cocok → fallback
  await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data: { status: "DEPRECATED" } });
  expect(await s.liveRecommendation(new Uint8Array([1]))).toBeNull();
});

test("Registri: hash harus 64 heksa dan status terbatas; endpoint kemampuan terautentikasi dan jujur", async () => {
  const u = await actor(["health_data_processing"]);
  const bad = async (fn: () => Promise<unknown>) => { try { await fn(); return false; } catch { return true; } };
  expect(await bad(() => register("RESEARCH_ONLY", { version: "v2", artifactSha256: "pendek" }))).toBe(true);
  expect(await bad(() => register("PRODUCTION", { version: "v3" }))).toBe(true);
  expect((await call("/api/me/ml/models")).status).toBe(401);
  const res = (await (await call("/api/me/ml/models", u.token)).json()) as any;
  expect(res.serving).toMatchObject({ configured: false });
  const m = res.models.find((x: any) => x.version === "vtest");
  expect(m).toMatchObject({ status: "DEPRECATED", usableForUsers: false });
  expect(JSON.stringify(res)).not.toMatch(/token|bearer|secret/i);
});

test("assist: APPROVED + consent memberi PERKIRAAN bila yakin; tidak yakin, gagal, versi tak cocok, atau tanpa consent → null; semuanya diaudit LIVE tanpa gambar", async () => {
  const yes = await actor(["health_data_processing", "model_inference"]);
  const no = await actor(["health_data_processing"]);
  await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data: { status: "APPROVED", approvedAt: new Date(), approvalNote: "Disetujui pemilik untuk uji otomatis (fixture)." } });
  const bytes = new Uint8Array([1, 2]);
  const sure = svc(() => reply());
  expect(await sure.s.assist(yes.id, bytes)).toEqual({ label: "Rendang", probability: 0.9, modelVersion: "vtest" });
  expect(await sure.s.assist(no.id, bytes)).toBeNull();
  expect(sure.calls()).toBe(1); // tanpa persetujuan foto tidak dikirim
  const unsure = svc(() => reply({ predictions: [{ label: "Rendang", probability: 0.6 }, { label: "Soto", probability: 0.3 }] }));
  expect(await unsure.s.assist(yes.id, bytes)).toBeNull(); // di bawah ambang → model dianggap tidak yakin
  expect(await svc(() => new Response("x", { status: 503 })).s.assist(yes.id, bytes)).toBeNull(); // Modal gagal → fallback, bukan galat
  expect(await svc(() => reply({ modelVersion: "lain" })).s.assist(yes.id, bytes)).toBeNull();
  const runs = await prisma.mlInferenceRun.findMany({ where: { userId: yes.id }, orderBy: { createdAt: "asc" } });
  expect(runs.map((r) => `${r.mode}:${r.status}`)).toEqual(["LIVE:OK", "LIVE:OK", "LIVE:UNAVAILABLE", "LIVE:VERSION_MISMATCH"]);
  await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data: { status: "RESEARCH_ONLY", approvedAt: null, approvalNote: null } });
  expect(await sure.s.assist(yes.id, bytes)).toBeNull(); // RESEARCH_ONLY: bayangan saja, tidak pernah dikembalikan
  expect((await prisma.mlInferenceRun.findFirst({ where: { userId: yes.id }, orderBy: { createdAt: "desc" } }))?.mode).toBe("SHADOW");
});

test("DB menolak status APPROVED tanpa waktu dan catatan persetujuan yang memadai", async () => {
  const fail = async (data: object) => { try { await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data }); return false; } catch { return true; } };
  expect(await fail({ status: "APPROVED" })).toBe(true);
  expect(await fail({ status: "APPROVED", approvedAt: new Date(), approvalNote: "singkat" })).toBe(true);
  expect(await fail({ status: "APPROVED", approvedAt: new Date(), approvalNote: "Disetujui pemilik, risiko lisensi dan evaluasi foto nyata diketahui." })).toBe(false);
  await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data: { status: "DEPRECATED", approvedAt: null, approvalNote: null } });
});

test("warmup: hanya untuk model APPROVED + consent, sekali per menit, tanpa audit, tanpa data pengguna; endpoint selalu 202 dan butuh login", async () => {
  const yes = await actor(["health_data_processing", "model_inference"]);
  const no = await actor(["health_data_processing"]);
  await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data: { status: "RESEARCH_ONLY", approvedAt: null, approvalNote: null } });
  const a = svc(() => reply());
  expect(await a.s.warmup(yes.id)).toEqual({ started: false, reason: "NOT_APPROVED" });
  await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data: { status: "APPROVED", approvedAt: new Date(), approvalNote: "Disetujui pemilik untuk uji otomatis (fixture)." } });
  expect(await a.s.warmup(no.id)).toEqual({ started: false, reason: "NO_CONSENT_OR_ERROR" });
  expect(await a.s.warmup(yes.id)).toEqual({ started: true });
  expect(await a.s.warmup(yes.id)).toEqual({ started: false, reason: "RECENT" });
  await Bun.sleep(20);
  expect(a.calls()).toBe(1);
  expect(await prisma.mlInferenceRun.count({ where: { userId: yes.id } })).toBe(0);
  expect((await call("/api/me/ml/warmup", undefined, {})).status).toBe(401);
  expect((await call("/api/me/ml/warmup", no.token, {})).status).toBe(202);
  await prisma.modelVersion.updateMany({ where: { modelKey: KEY }, data: { status: "DEPRECATED", approvedAt: null, approvalNote: null } });
});
