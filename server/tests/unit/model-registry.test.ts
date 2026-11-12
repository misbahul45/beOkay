import { expect, test } from "bun:test";
import { evaluationFromMetrics, validateRegistration, type ModelCard, type Registration } from "../../src/features/ml/model-registry.ts";

const card: ModelCard = {
  modelKey: "dish-classifier",
  featureSchemaVersion: "image-224-imagenet-norm-v1",
  intendedUse: "Mengenali nama hidangan untuk evaluasi bayangan saja.",
  trainingDataProvenance: "Dataset Kaggle hasil scraping, lisensi tidak tercantum.",
  endpointRef: "modal:beokay-dish-classifier/DishClassifier.web",
  architecture: "mobilenet_v3_large",
};
const metrics = {
  model: "mobilenet_v3_large",
  epochs: 8,
  seed: 1337,
  temperature: 0.64,
  classes: ["Rendang", "Soto", "Sate"],
  test_full: { n: 647, accuracy: 0.969, top3_accuracy: 0.995, ece_raw: 0.1, ece_calibrated: 0.01, per_class: {}, confusion_matrix: [[1]] },
  test_deduplicated: { n: 445, accuracy: 0.955, top3_accuracy: 0.993, ece_raw: 0.1, ece_calibrated: 0.02 },
  audit: { test: { total: 647, exact_dup_of_train: 114, "near_dup_of_train(<=3 bits)": 88, clean: 445 } },
  limitations: ["Akurasi pada foto pengguna nyata tidak diketahui."],
};
const reg = (over: Partial<Registration> = {}, evalOver: object = {}): Registration => ({
  modelKey: card.modelKey,
  version: "v2-20261120",
  artifactSha256: "a".repeat(64),
  featureSchemaVersion: card.featureSchemaVersion,
  intendedUse: card.intendedUse,
  trainingDataProvenance: card.trainingDataProvenance,
  endpointRef: card.endpointRef,
  evaluation: { ...evaluationFromMetrics(metrics, card), ...evalOver },
  ...over,
});

test("evaluasi diringkas dari metrics.json: audit kebocoran dan uji tanpa duplikat ikut, matriks per kelas tidak", () => {
  const e = evaluationFromMetrics(metrics, card) as any;
  expect(e.leakage_audit).toEqual({ test_clean: 445, test_exact_dup_of_train: 114, test_near_dup_of_train: 88 });
  expect(e.test_deduplicated.accuracy).toBe(0.955);
  expect(e.test_full).not.toHaveProperty("confusion_matrix");
  expect(e.classes).toEqual(["Rendang", "Soto", "Sate"]);
});

test("pendaftaran lengkap lolos validasi", () => {
  expect(validateRegistration(reg(), ["Rendang", "Soto", "Sate"])).toEqual([]);
});

test("pendaftaran ditolak tanpa uji tanpa duplikat, audit kebocoran, batasan, atau dengan SHA/versi/endpoint keliru", () => {
  expect(validateRegistration(reg({}, { test_deduplicated: null }))).toContain("EVALUATION_DEDUPLICATED_MISSING");
  expect(validateRegistration(reg({}, { test_deduplicated: { n: 10, accuracy: 1.4 } }))).toContain("EVALUATION_DEDUPLICATED_MISSING");
  expect(validateRegistration(reg({}, { leakage_audit: {} }))).toContain("LEAKAGE_AUDIT_MISSING");
  expect(validateRegistration(reg({}, { limitations: [] }))).toContain("LIMITATIONS_MISSING");
  expect(validateRegistration(reg({ artifactSha256: "xyz" }))).toContain("SHA256_INVALID");
  expect(validateRegistration(reg({ version: "latest" }))).toContain("VERSION_INVALID");
  expect(validateRegistration(reg({ endpointRef: "https://example.com" }))).toContain("ENDPOINT_REF_INVALID");
  expect(validateRegistration(reg({ intendedUse: "nama" }))).toContain("INTENDED_USE_TOO_SHORT");
  expect(validateRegistration(reg(), ["Soto", "Rendang", "Sate"])).toContain("CLASSES_MISMATCH");
  expect(validateRegistration(reg({}, { classes: ["Soto", "Soto"] }))).toContain("CLASSES_INVALID");
});
