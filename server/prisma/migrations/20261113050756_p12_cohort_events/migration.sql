-- AlterTable
ALTER TABLE "health_profiles" ADD COLUMN     "journey" TEXT NOT NULL DEFAULT 'UNDETERMINED',
ADD COLUMN     "journey_set_at" TIMESTAMPTZ(6),
ADD COLUMN     "journey_source" TEXT,
ADD COLUMN     "risk_statement" TEXT;

-- AlterTable
ALTER TABLE "outbox_events" ADD COLUMN     "consent_scope" TEXT,
ADD COLUMN     "correlation_id" TEXT,
ADD COLUMN     "occurred_at" TIMESTAMPTZ(6),
ADD COLUMN     "provenance" JSONB,
ADD COLUMN     "quality" TEXT,
ADD COLUMN     "received_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "revision" INTEGER,
ADD COLUMN     "schema_version" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN     "source" TEXT,
ADD COLUMN     "source_record_id" TEXT,
ADD COLUMN     "timezone" TEXT;

-- CreateTable
CREATE TABLE "daily_behavior_facts" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "local_date" DATE NOT NULL,
    "timezone" TEXT NOT NULL,
    "active_minutes" INTEGER NOT NULL DEFAULT 0,
    "active_minutes_manual" INTEGER NOT NULL DEFAULT 0,
    "active_minutes_device" INTEGER NOT NULL DEFAULT 0,
    "session_count" INTEGER NOT NULL DEFAULT 0,
    "longest_session_minutes" INTEGER,
    "steps" INTEGER,
    "steps_sources" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "sleep_minutes" INTEGER,
    "meals_logged" INTEGER NOT NULL DEFAULT 0,
    "meal_categories" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "glucose_checks" INTEGER NOT NULL DEFAULT 0,
    "medication_confirmed" INTEGER NOT NULL DEFAULT 0,
    "goal_checkins" INTEGER NOT NULL DEFAULT 0,
    "sources" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "dirty" BOOLEAN NOT NULL DEFAULT false,
    "computation_version" TEXT NOT NULL,
    "computed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "daily_behavior_facts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "daily_behavior_facts_user_id_local_date_key" ON "daily_behavior_facts"("user_id", "local_date");

-- CreateIndex
CREATE INDEX "outbox_events_user_id_type_created_at_idx" ON "outbox_events"("user_id", "type", "created_at" DESC);

-- AddForeignKey
ALTER TABLE "daily_behavior_facts" ADD CONSTRAINT "daily_behavior_facts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

UPDATE "health_profiles" SET "journey" = CASE WHEN "eligibility_status" = 'eligible' THEN 'T2DM_SUPPORT' ELSE 'UNDETERMINED' END, "journey_source" = 'backfill_p12', "journey_set_at" = now();

ALTER TABLE "health_profiles" ADD CONSTRAINT "health_profiles_journey_check" CHECK ("journey" IN ('PREVENTION','T2DM_SUPPORT','WELLNESS','UNDETERMINED'));
ALTER TABLE "health_profiles" ADD CONSTRAINT "health_profiles_risk_statement_check" CHECK ("risk_statement" IS NULL OR "risk_statement" IN ('prediabetes_told','at_risk_told','none','undisclosed'));
ALTER TABLE "daily_behavior_facts" ADD CONSTRAINT "daily_behavior_facts_nonneg_check" CHECK ("active_minutes" >= 0 AND "active_minutes_manual" >= 0 AND "active_minutes_device" >= 0 AND "session_count" >= 0 AND "meals_logged" >= 0 AND "glucose_checks" >= 0 AND "medication_confirmed" >= 0 AND "goal_checkins" >= 0 AND ("steps" IS NULL OR "steps" >= 0) AND ("sleep_minutes" IS NULL OR "sleep_minutes" >= 0));
CREATE INDEX "daily_behavior_facts_dirty_idx" ON "daily_behavior_facts"("user_id") WHERE "dirty";

ALTER TABLE "daily_steps" ADD COLUMN "data_origin" TEXT;
ALTER TABLE "sleep_sessions" ADD COLUMN "data_origin" TEXT;
ALTER TABLE "activity_sessions" ADD COLUMN "data_origin" TEXT, ADD COLUMN "recording_method" TEXT, ADD COLUMN "device_type" TEXT;
ALTER TABLE "activity_sessions" ADD CONSTRAINT "activity_sessions_recording_method_check" CHECK ("recording_method" IS NULL OR "recording_method" IN ('automatic','active','manual','unknown'));

ALTER TABLE "consent_records" DROP CONSTRAINT "consent_records_purpose_valid";
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_purpose_valid"
  CHECK ("purpose" IN ('health_data_processing','descriptive_summaries','product_analytics','personalized_ai','community_membership','challenge_participation','leaderboard_visibility','model_inference','ai_text_generation','ai_message_understanding','companion_sharing','device_data_coaching','social_outcomes_memory'));

ALTER TABLE "feature_flags" DROP CONSTRAINT "feature_flags_valid";
ALTER TABLE "feature_flags" ADD CONSTRAINT "feature_flags_valid" CHECK (
  "key" IN ('assistant','conversation','coaching','community','ml_inference','food_vision','web_discovery','analytics','push','llm_router','companion','cgm','projection_consumers','skill_registry','react_llm_planner','jitai_v3')
  AND ("note" IS NULL OR length("note") <= 300)
  AND length("updated_by") BETWEEN 1 AND 120
);
