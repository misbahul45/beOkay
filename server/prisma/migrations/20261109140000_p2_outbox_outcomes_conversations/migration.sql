-- Percakapan multi-giliran: giliran lanjutan menunjuk run sebelumnya (hanya milik pengguna yang sama, dijaga di aplikasi).
ALTER TABLE "agent_runs" ADD COLUMN "parent_run_id" UUID, ADD COLUMN "turn" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "agent_runs" ADD CONSTRAINT "agent_runs_parent_run_id_fkey" FOREIGN KEY ("parent_run_id") REFERENCES "agent_runs"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "agent_runs" ADD CONSTRAINT "agent_runs_turn_valid" CHECK ("turn" BETWEEN 1 AND 20 AND ("parent_run_id" IS NOT NULL OR "turn" = 1));
CREATE INDEX "agent_runs_parent_run_id_idx" ON "agent_runs"("parent_run_id");

-- Tujuan consent baru: teks saran ditulis model bahasa pihak ketiga (Mistral) dari fakta saran saja. Tanpa naik versi kebijakan.
ALTER TABLE "consent_records" DROP CONSTRAINT "consent_records_purpose_valid";
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_purpose_valid"
  CHECK ("purpose" IN ('health_data_processing','descriptive_summaries','product_analytics','personalized_ai','community_membership','challenge_participation','leaderboard_visibility','model_inference','ai_text_generation'));

-- Persetujuan model: APPROVED wajib punya waktu dan catatan persetujuan pemilik.
ALTER TABLE "model_versions" ADD COLUMN "approved_at" TIMESTAMPTZ(6), ADD COLUMN "approval_note" TEXT;
ALTER TABLE "model_versions" ADD CONSTRAINT "model_versions_approval_recorded"
  CHECK ("status" <> 'APPROVED' OR ("approved_at" IS NOT NULL AND "approval_note" IS NOT NULL AND length("approval_note") >= 20));

-- Outbox transaksional.
CREATE TABLE "outbox_events" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "type" TEXT NOT NULL,
    "payload" JSONB NOT NULL DEFAULT '{}',
    "dedupe_key" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "available_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processed_at" TIMESTAMPTZ(6),
    "last_error" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "outbox_events_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "outbox_events_valid" CHECK ("status" IN ('PENDING','DONE','DEAD') AND "attempts" >= 0)
);
CREATE UNIQUE INDEX "outbox_events_dedupe_key_key" ON "outbox_events"("dedupe_key");
CREATE INDEX "outbox_events_status_available_at_idx" ON "outbox_events"("status", "available_at");
ALTER TABLE "outbox_events" ADD CONSTRAINT "outbox_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Hasil terukur dari catatan nyata.
CREATE TABLE "recommendation_outcomes" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "recommendation_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "evidence_type" TEXT NOT NULL,
    "evidence_id" UUID NOT NULL,
    "observed_at" TIMESTAMPTZ(6) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "recommendation_outcomes_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "recommendation_outcomes_valid" CHECK ("kind" IN ('MEAL_LOGGED','ACTIVITY_LOGGED') AND "evidence_type" IN ('meal_item','activity_session'))
);
CREATE UNIQUE INDEX "recommendation_outcomes_recommendation_id_key" ON "recommendation_outcomes"("recommendation_id");
CREATE INDEX "recommendation_outcomes_user_id_observed_at_idx" ON "recommendation_outcomes"("user_id", "observed_at" DESC);
ALTER TABLE "recommendation_outcomes" ADD CONSTRAINT "recommendation_outcomes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "recommendation_outcomes" ADD CONSTRAINT "recommendation_outcomes_recommendation_id_fkey" FOREIGN KEY ("recommendation_id") REFERENCES "recommendations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
