import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { evaluationFromMetrics, registerModel, validateRegistration, type ModelCard, type Registration, type TrainingMetrics } from "../../src/features/ml/model-registry.ts";

const args = process.argv.slice(2);
const DEPRECATED_KEYS = new Set(["dish-classifier"]);
const flag = (name: string) => {
  const i = args.indexOf(name);
  if (i < 0) return undefined;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
};
const dryRun = args.includes("--dry-run");
if (dryRun) args.splice(args.indexOf("--dry-run"), 1);
const cardPath = flag("--card");
const expectSha = flag("--expect-sha");
const [modelKey, version, dir] = args;

if (!modelKey || !version || !dir) {
  console.error("Pemakaian: register-model.ts <modelKey> <versi> <folder-artefak> [--expect-sha <sha256>] [--card <model-card.json>] [--dry-run]");
  console.error("Folder artefak berisi keluaran pelatihan: model.pt, metrics.json, classes.json.");
  process.exit(2);
}

const readJson = async <T>(path: string): Promise<T> => {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    console.error(`Berkas tidak ditemukan: ${path}`);
    process.exit(1);
  }
  return (await file.json()) as T;
};

if (DEPRECATED_KEYS.has(modelKey) && !args.includes("--allow-deprecated-key")) {
  console.error(`${modelKey} dihentikan sejak 3.0 Fase 10 (A-8): kelas tidak relevan untuk hidangan Indonesia dan lisensi dataset belum jelas. Tambahkan --allow-deprecated-key hanya untuk riset dengan dataset berlisensi.`);
  process.exit(1);
}
const card = await readJson<ModelCard>(cardPath ?? `${import.meta.dir}/model-cards/${modelKey}.json`);
if (card.modelKey !== modelKey) {
  console.error(`Kartu model untuk ${card.modelKey}, bukan ${modelKey}.`);
  process.exit(1);
}
const metrics = await readJson<TrainingMetrics>(`${dir}/metrics.json`);
const classesFile = (await readJson<{ classes: string[] }>(`${dir}/classes.json`)).classes;
const model = Bun.file(`${dir}/model.pt`);
if (!(await model.exists())) {
  console.error(`Berkas tidak ditemukan: ${dir}/model.pt`);
  process.exit(1);
}
const sha = new Bun.CryptoHasher("sha256").update(await model.arrayBuffer()).digest("hex");
if (expectSha && expectSha.toLowerCase() !== sha) {
  console.error(`SHA-256 model.pt (${sha}) tidak sama dengan --expect-sha (${expectSha}).`);
  process.exit(1);
}

const registration: Registration = {
  modelKey,
  version,
  artifactSha256: sha,
  featureSchemaVersion: card.featureSchemaVersion,
  intendedUse: card.intendedUse,
  trainingDataProvenance: card.trainingDataProvenance,
  endpointRef: card.endpointRef,
  evaluation: evaluationFromMetrics(metrics, card),
};
const errors = validateRegistration(registration, classesFile);
if (errors.length) {
  console.error(JSON.stringify({ ok: false, errors }));
  process.exit(1);
}
if (dryRun) {
  console.log(JSON.stringify({ ok: true, dryRun: true, modelKey, version, artifactSha256: sha, status: "RESEARCH_ONLY" }));
  process.exit(0);
}
try {
  const result = await registerModel(registration);
  console.log(JSON.stringify({ ok: true, modelKey, version, artifactSha256: sha, ...result }));
} catch (e) {
  console.error(JSON.stringify({ ok: false, error: (e as { code?: string }).code ?? String(e) }));
  process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
