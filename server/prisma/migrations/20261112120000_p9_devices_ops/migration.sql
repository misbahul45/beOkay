-- AlterTable
ALTER TABLE "vital_measurements" ADD COLUMN     "external_id" TEXT;

-- CreateTable
CREATE TABLE "daily_steps" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "local_date" DATE NOT NULL,
    "steps" INTEGER NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'health_connect',
    "synced_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "daily_steps_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sleep_sessions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "started_at" TIMESTAMPTZ(6) NOT NULL,
    "ended_at" TIMESTAMPTZ(6) NOT NULL,
    "duration_minutes" INTEGER NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'health_connect',
    "external_id" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sleep_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device_import_preferences" (
    "user_id" UUID NOT NULL,
    "workouts" BOOLEAN NOT NULL DEFAULT false,
    "steps" BOOLEAN NOT NULL DEFAULT false,
    "weight" BOOLEAN NOT NULL DEFAULT false,
    "glucose" BOOLEAN NOT NULL DEFAULT false,
    "sleep" BOOLEAN NOT NULL DEFAULT false,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "device_import_preferences_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "share_links" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "scope" TEXT NOT NULL DEFAULT 'summary',
    "period_days" INTEGER NOT NULL,
    "label" TEXT,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),
    "last_accessed_at" TIMESTAMPTZ(6),
    "access_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "share_links_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "daily_steps_user_id_source_local_date_key" ON "daily_steps"("user_id", "source", "local_date");

-- CreateIndex
CREATE INDEX "sleep_sessions_user_id_started_at_idx" ON "sleep_sessions"("user_id", "started_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "sleep_sessions_user_id_source_external_id_key" ON "sleep_sessions"("user_id", "source", "external_id");

-- CreateIndex
CREATE UNIQUE INDEX "share_links_token_hash_key" ON "share_links"("token_hash");

-- CreateIndex
CREATE INDEX "share_links_user_id_created_at_idx" ON "share_links"("user_id", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "glucose_observations_user_id_source_source_record_id_key" ON "glucose_observations"("user_id", "source", "source_record_id");

-- CreateIndex
CREATE UNIQUE INDEX "vital_measurements_user_id_source_external_id_key" ON "vital_measurements"("user_id", "source", "external_id");

-- AddForeignKey
ALTER TABLE "daily_steps" ADD CONSTRAINT "daily_steps_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sleep_sessions" ADD CONSTRAINT "sleep_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_import_preferences" ADD CONSTRAINT "device_import_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "share_links" ADD CONSTRAINT "share_links_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE glucose_observations DROP CONSTRAINT glucose_observations_valid;
ALTER TABLE glucose_observations ADD CONSTRAINT glucose_observations_valid CHECK (
  (
    (source = 'manual_glucometer' AND measurement_type = 'capillary_blood' AND source_record_id IS NULL AND quality_status IN ('user_reported','needs_review'))
    OR (source = 'health_connect' AND measurement_type IN ('capillary_blood','interstitial_fluid','unknown') AND source_record_id IS NOT NULL AND length(source_record_id) BETWEEN 1 AND 200 AND quality_status IN ('device_reported','needs_review'))
  )
  AND original_unit IN ('mg/dL','mmol/L') AND original_value > 0 AND value_mg_dl BETWEEN 1 AND 2000
  AND value_mg_dl=CASE original_unit WHEN 'mg/dL' THEN original_value ELSE original_value*18.016 END
  AND meal_context IN ('fasting','before_meal','after_meal','bedtime','other','unknown')
  AND quality_flags <@ ARRAY['user_flagged']::text[] AND cardinality(quality_flags)<=1
  AND ((quality_status='needs_review')=(cardinality(quality_flags)=1))
  AND version>0 AND length(create_hash)=64 AND measured_at>='1900-01-01'::timestamptz
  AND (notes IS NULL OR length(notes)<=2000)
);

ALTER TABLE vital_measurements ADD CONSTRAINT vital_measurements_external_id CHECK (
  (source = 'manual' AND external_id IS NULL) OR (source = 'health_connect' AND external_id IS NOT NULL AND length(external_id) BETWEEN 1 AND 200)
);

ALTER TABLE daily_steps ADD CONSTRAINT daily_steps_valid CHECK (
  source IN ('health_connect') AND steps BETWEEN 0 AND 200000 AND local_date >= '2000-01-01'
);

ALTER TABLE sleep_sessions ADD CONSTRAINT sleep_sessions_valid CHECK (
  source IN ('health_connect') AND ended_at > started_at AND duration_minutes BETWEEN 1 AND 1440
  AND length(external_id) BETWEEN 1 AND 200
);

ALTER TABLE share_links ADD CONSTRAINT share_links_valid CHECK (
  scope IN ('summary') AND period_days IN (14, 30, 90) AND length(token_hash) = 64
  AND (label IS NULL OR length(label) BETWEEN 1 AND 60) AND expires_at > created_at
  AND expires_at <= created_at + interval '7 days' AND access_count >= 0
);

ALTER TABLE behavior_goals DROP CONSTRAINT behavior_goals_valid;
ALTER TABLE behavior_goals ADD CONSTRAINT behavior_goals_valid CHECK (
 goal_type IN ('manual_checkins','activity_minutes','walking_sessions','record_meals','record_glucose','daily_steps')
 AND period IN ('daily','weekly')
 AND status IN ('active','paused','completed','archived')
 AND target_value > 0
 AND (end_date IS NULL OR end_date >= start_date));

