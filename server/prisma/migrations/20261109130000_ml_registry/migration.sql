-- Registri model ML dan audit inferensi. Hanya model APPROVED yang boleh memengaruhi hasil untuk pengguna;
-- RESEARCH_ONLY/SHADOW hanya berjalan di mode bayangan (hasil dicatat, tidak ditampilkan).
CREATE TABLE "model_versions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "model_key" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "artifact_sha256" TEXT NOT NULL,
    "feature_schema_version" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "intended_use" TEXT NOT NULL,
    "training_data_provenance" TEXT NOT NULL,
    "evaluation" JSONB NOT NULL,
    "endpoint_ref" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "model_versions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "model_versions_valid" CHECK ("status" IN ('RESEARCH_ONLY','SHADOW','APPROVED','DEPRECATED') AND "artifact_sha256" ~ '^[0-9a-f]{64}$')
);
CREATE UNIQUE INDEX "model_versions_model_key_version_key" ON "model_versions"("model_key", "version");

CREATE TABLE "ml_inference_runs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "model_version_id" UUID NOT NULL,
    "mode" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "latency_ms" INTEGER NOT NULL,
    "input_bytes" INTEGER NOT NULL,
    "top_label" TEXT,
    "top_probability" DECIMAL(5,4),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ml_inference_runs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "ml_inference_runs_valid" CHECK ("mode" IN ('SHADOW','LIVE') AND "status" IN ('OK','TIMEOUT','UNAVAILABLE','INVALID_RESPONSE','CIRCUIT_OPEN','VERSION_MISMATCH') AND "latency_ms" >= 0 AND "input_bytes" >= 0 AND ("top_probability" IS NULL OR "top_probability" BETWEEN 0 AND 1))
);
CREATE INDEX "ml_inference_runs_model_version_id_created_at_idx" ON "ml_inference_runs"("model_version_id", "created_at" DESC);
ALTER TABLE "ml_inference_runs" ADD CONSTRAINT "ml_inference_runs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ml_inference_runs" ADD CONSTRAINT "ml_inference_runs_model_version_id_fkey" FOREIGN KEY ("model_version_id") REFERENCES "model_versions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "consent_records" DROP CONSTRAINT "consent_records_purpose_valid";
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_purpose_valid"
  CHECK ("purpose" IN ('health_data_processing','descriptive_summaries','product_analytics','personalized_ai','community_membership','challenge_participation','leaderboard_visibility','model_inference'));
