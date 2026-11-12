import { prisma } from "../../infrastructure/database/prisma.ts";
import { conflict } from "../../shared/errors/app-error.ts";
import { logEvent } from "../../shared/http/logger.ts";

export type ModelCard = {
  modelKey: string;
  featureSchemaVersion: string;
  intendedUse: string;
  trainingDataProvenance: string;
  endpointRef: string;
  architecture: string;
  kernel?: string;
};

type SplitMetrics = { n?: number; accuracy?: number; top3_accuracy?: number; ece_raw?: number; ece_calibrated?: number };
export type TrainingMetrics = {
  model?: string;
  pretrained?: string;
  epochs?: number;
  seed?: number;
  temperature?: number;
  classes?: string[];
  test_full?: SplitMetrics | null;
  test_deduplicated?: SplitMetrics | null;
  audit?: { test?: Record<string, number> };
  limitations?: string[];
};

export type Registration = {
  modelKey: string;
  version: string;
  artifactSha256: string;
  featureSchemaVersion: string;
  intendedUse: string;
  trainingDataProvenance: string;
  endpointRef: string;
  evaluation: Record<string, unknown>;
};

const split = (m: SplitMetrics | null | undefined) =>
  m ? { n: m.n, accuracy: m.accuracy, top3_accuracy: m.top3_accuracy, ece_raw: m.ece_raw, ece_calibrated: m.ece_calibrated } : null;

export function evaluationFromMetrics(metrics: TrainingMetrics, card: ModelCard): Record<string, unknown> {
  const test = metrics.audit?.test ?? {};
  return {
    architecture: metrics.model ?? card.architecture,
    pretrained: metrics.pretrained ?? null,
    kernel: card.kernel ?? null,
    seed: metrics.seed ?? null,
    epochs: metrics.epochs ?? null,
    temperature: metrics.temperature ?? null,
    classes: metrics.classes ?? [],
    test_full: split(metrics.test_full),
    test_deduplicated: split(metrics.test_deduplicated),
    leakage_audit: {
      test_clean: test.clean ?? null,
      test_exact_dup_of_train: test.exact_dup_of_train ?? null,
      test_near_dup_of_train: test["near_dup_of_train(<=3 bits)"] ?? null,
    },
    limitations: metrics.limitations ?? [],
  };
}

const isProbability = (v: unknown) => typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 1;

export function validateRegistration(r: Registration, classesFile?: string[]): string[] {
  const errors: string[] = [];
  if (!/^[a-z0-9][a-z0-9-]{2,63}$/.test(r.modelKey)) errors.push("MODEL_KEY_INVALID");
  if (!/^v[0-9][0-9a-z.-]{0,40}$/.test(r.version)) errors.push("VERSION_INVALID");
  if (!/^[0-9a-f]{64}$/.test(r.artifactSha256)) errors.push("SHA256_INVALID");
  if (!/^[a-z0-9][a-z0-9.-]{2,63}$/.test(r.featureSchemaVersion)) errors.push("FEATURE_SCHEMA_INVALID");
  if (r.intendedUse.trim().length < 30) errors.push("INTENDED_USE_TOO_SHORT");
  if (r.trainingDataProvenance.trim().length < 30) errors.push("PROVENANCE_TOO_SHORT");
  if (!/^modal:[a-z0-9-]+\/[A-Za-z0-9_.]+$/.test(r.endpointRef)) errors.push("ENDPOINT_REF_INVALID");
  const e = r.evaluation as { test_deduplicated?: SplitMetrics | null; leakage_audit?: { test_clean?: unknown }; limitations?: unknown; classes?: unknown };
  const dedup = e.test_deduplicated;
  if (!dedup || !isProbability(dedup.accuracy) || !Number.isInteger(dedup.n) || (dedup.n ?? 0) <= 0) errors.push("EVALUATION_DEDUPLICATED_MISSING");
  if (typeof e.leakage_audit?.test_clean !== "number") errors.push("LEAKAGE_AUDIT_MISSING");
  if (!Array.isArray(e.limitations) || e.limitations.length === 0 || e.limitations.some((l) => typeof l !== "string" || !l.trim())) errors.push("LIMITATIONS_MISSING");
  const classes = Array.isArray(e.classes) ? (e.classes as unknown[]) : [];
  if (classes.length < 2 || classes.some((c) => typeof c !== "string") || new Set(classes).size !== classes.length) errors.push("CLASSES_INVALID");
  if (classesFile && JSON.stringify(classesFile) !== JSON.stringify(classes)) errors.push("CLASSES_MISMATCH");
  return errors;
}

export async function registerModel(r: Registration): Promise<{ outcome: "CREATED" | "UNCHANGED"; id: string; status: string }> {
  const errors = validateRegistration(r);
  if (errors.length) throw conflict("MODEL_REGISTRATION_INVALID", "Pendaftaran model tidak lengkap.", { errors });
  const existing = await prisma.modelVersion.findUnique({ where: { modelKey_version: { modelKey: r.modelKey, version: r.version } } });
  if (existing) {
    if (existing.artifactSha256 !== r.artifactSha256) throw conflict("MODEL_VERSION_SHA_CONFLICT", "Versi ini sudah terdaftar dengan artefak lain. Pakai nomor versi baru.");
    return { outcome: "UNCHANGED", id: existing.id, status: existing.status };
  }
  const row = await prisma.modelVersion.create({
    data: {
      modelKey: r.modelKey,
      version: r.version,
      artifactSha256: r.artifactSha256,
      featureSchemaVersion: r.featureSchemaVersion,
      status: "RESEARCH_ONLY",
      intendedUse: r.intendedUse.trim(),
      trainingDataProvenance: r.trainingDataProvenance.trim(),
      evaluation: r.evaluation as object,
      endpointRef: r.endpointRef,
    },
  });
  logEvent("info", "model_registered", { modelKey: row.modelKey, version: row.version, status: row.status });
  return { outcome: "CREATED", id: row.id, status: row.status };
}
