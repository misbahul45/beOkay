import { afterAll, beforeAll, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const KEY = `test-registry-${crypto.randomUUID().slice(0, 8)}`;
let dir = "";

const metrics = {
  model: "mobilenet_v3_large",
  epochs: 8,
  seed: 1337,
  classes: ["Rendang", "Soto"],
  test_full: { n: 100, accuracy: 0.95, top3_accuracy: 1, ece_raw: 0.1, ece_calibrated: 0.02 },
  test_deduplicated: { n: 80, accuracy: 0.93, top3_accuracy: 1, ece_raw: 0.1, ece_calibrated: 0.03 },
  audit: { test: { total: 100, exact_dup_of_train: 12, "near_dup_of_train(<=3 bits)": 8, clean: 80 } },
  limitations: ["Data sintetis untuk uji."],
};

async function writeArtifacts(bytes: Uint8Array, m: object = metrics) {
  await Bun.write(join(dir, "model.pt"), bytes);
  await Bun.write(join(dir, "metrics.json"), JSON.stringify(m));
  await Bun.write(join(dir, "classes.json"), JSON.stringify({ classes: ["Rendang", "Soto"] }));
}
const sha = (b: Uint8Array) => new Bun.CryptoHasher("sha256").update(b).digest("hex");

async function run(version: string, extra: string[] = []) {
  const p = Bun.spawn(["bun", "run", "scripts/ml/register-model.ts", KEY, version, dir, "--card", join(dir, "card.json"), ...extra], { cwd: join(import.meta.dir, "../.."), stdout: "pipe", stderr: "pipe", env: process.env });
  const [out, err] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text()]);
  return { code: await p.exited, out: out.trim().split("\n").filter((l) => l.startsWith("{")).pop() ?? "", err };
}

beforeAll(async () => {
  if (process.env.NODE_ENV !== "test") throw new Error("Isolated test stack required");
  dir = await mkdtemp(join(tmpdir(), "registry-"));
  await Bun.write(
    join(dir, "card.json"),
    JSON.stringify({ modelKey: KEY, featureSchemaVersion: "image-224-imagenet-norm-v1", intendedUse: "Uji pendaftaran registri model, bukan model sungguhan.", trainingDataProvenance: "Artefak sintetis yang dibuat oleh tes integrasi.", endpointRef: "modal:beokay-test/Classifier.web", architecture: "mobilenet_v3_large" }),
  );
});
afterAll(async () => {
  await prisma.modelVersion.deleteMany({ where: { modelKey: KEY } });
  await rm(dir, { recursive: true, force: true });
});

test("skrip mendaftarkan versi baru sebagai RESEARCH_ONLY dengan SHA dari model.pt", async () => {
  const bytes = crypto.getRandomValues(new Uint8Array(256));
  await writeArtifacts(bytes);
  const dry = await run("v1-test", ["--dry-run"]);
  expect(dry.code).toBe(0);
  expect(await prisma.modelVersion.count({ where: { modelKey: KEY } })).toBe(0);

  const first = await run("v1-test", ["--expect-sha", sha(bytes)]);
  expect(first.code).toBe(0);
  expect(JSON.parse(first.out)).toMatchObject({ ok: true, outcome: "CREATED", status: "RESEARCH_ONLY", artifactSha256: sha(bytes) });
  const row = await prisma.modelVersion.findUniqueOrThrow({ where: { modelKey_version: { modelKey: KEY, version: "v1-test" } } });
  expect(row).toMatchObject({ status: "RESEARCH_ONLY", approvedAt: null, artifactSha256: sha(bytes), endpointRef: "modal:beokay-test/Classifier.web" });
  expect((row.evaluation as any).test_deduplicated.accuracy).toBe(0.93);
  expect((row.evaluation as any).leakage_audit.test_clean).toBe(80);
});

test("idempoten untuk artefak yang sama; artefak lain pada versi yang sama ditolak", async () => {
  const again = await run("v1-test");
  expect(again.code).toBe(0);
  expect(JSON.parse(again.out)).toMatchObject({ outcome: "UNCHANGED" });

  await writeArtifacts(crypto.getRandomValues(new Uint8Array(256)));
  const clash = await run("v1-test");
  expect(clash.code).toBe(1);
  expect(clash.err).toContain("MODEL_VERSION_SHA_CONFLICT");
  expect(await prisma.modelVersion.count({ where: { modelKey: KEY } })).toBe(1);
});

test("SHA yang tidak cocok dan evaluasi tanpa uji tanpa duplikat ditolak tanpa menulis apa pun", async () => {
  const bytes = crypto.getRandomValues(new Uint8Array(64));
  await writeArtifacts(bytes);
  const wrong = await run("v2-test", ["--expect-sha", "0".repeat(64)]);
  expect(wrong.code).toBe(1);
  expect(wrong.err).toContain("tidak sama");

  await writeArtifacts(bytes, { ...metrics, test_deduplicated: null });
  const noDedup = await run("v2-test");
  expect(noDedup.code).toBe(1);
  expect(noDedup.err).toContain("EVALUATION_DEDUPLICATED_MISSING");
  expect(await prisma.modelVersion.count({ where: { modelKey: KEY, version: "v2-test" } })).toBe(0);
});
