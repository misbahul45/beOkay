ALTER TABLE "device_import_preferences" ADD COLUMN "heart_rate" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "resting_heart_rate" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "sleep_sessions" ADD COLUMN "device_type" TEXT,
ADD COLUMN "recording_method" TEXT,
ADD COLUMN "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE TABLE "wearable_heart_rate_buckets" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'health_connect',
    "data_origin" TEXT NOT NULL DEFAULT 'unknown',
    "bucket_start" TIMESTAMPTZ(6) NOT NULL,
    "bpm_min" INTEGER NOT NULL,
    "bpm_max" INTEGER NOT NULL,
    "bpm_avg" DECIMAL(6,2) NOT NULL,
    "sample_count" INTEGER NOT NULL,
    "recording_method" TEXT,
    "device_type" TEXT,
    "quality_status" TEXT NOT NULL DEFAULT 'device_reported',
    "quality_flags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "imported_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wearable_heart_rate_buckets_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "wearable_resting_heart_rates" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'health_connect',
    "data_origin" TEXT,
    "external_id" TEXT NOT NULL,
    "measured_at" TIMESTAMPTZ(6) NOT NULL,
    "bpm" INTEGER NOT NULL,
    "recording_method" TEXT,
    "device_type" TEXT,
    "quality_status" TEXT NOT NULL DEFAULT 'device_reported',
    "quality_flags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "imported_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wearable_resting_heart_rates_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "device_sync_checkpoints" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'health_connect',
    "metric" TEXT NOT NULL,
    "cursor" TEXT,
    "last_attempt_at" TIMESTAMPTZ(6),
    "last_success_at" TIMESTAMPTZ(6),
    "last_error_code" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "device_sync_checkpoints_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "wearable_heart_rate_buckets_user_id_bucket_start_idx" ON "wearable_heart_rate_buckets"("user_id", "bucket_start" DESC);

CREATE UNIQUE INDEX "wearable_heart_rate_buckets_user_id_source_data_origin_buck_key" ON "wearable_heart_rate_buckets"("user_id", "source", "data_origin", "bucket_start");

CREATE INDEX "wearable_resting_heart_rates_user_id_measured_at_idx" ON "wearable_resting_heart_rates"("user_id", "measured_at" DESC);

CREATE UNIQUE INDEX "wearable_resting_heart_rates_user_id_source_external_id_key" ON "wearable_resting_heart_rates"("user_id", "source", "external_id");

CREATE UNIQUE INDEX "device_sync_checkpoints_user_id_source_metric_key" ON "device_sync_checkpoints"("user_id", "source", "metric");

ALTER TABLE "wearable_heart_rate_buckets" ADD CONSTRAINT "wearable_heart_rate_buckets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "wearable_resting_heart_rates" ADD CONSTRAINT "wearable_resting_heart_rates_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "device_sync_checkpoints" ADD CONSTRAINT "device_sync_checkpoints_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "wearable_heart_rate_buckets" ADD CONSTRAINT "wearable_heart_rate_buckets_valid" CHECK (
  "source" IN ('health_connect','simulated')
  AND length("data_origin") BETWEEN 1 AND 200
  AND "bpm_min" BETWEEN 20 AND 300
  AND "bpm_max" BETWEEN 20 AND 300
  AND "bpm_min" <= "bpm_max"
  AND "bpm_avg" BETWEEN "bpm_min" AND "bpm_max"
  AND "sample_count" BETWEEN 1 AND 100000
  AND "quality_status" IN ('device_reported','needs_review')
  AND ("recording_method" IS NULL OR "recording_method" IN ('automatic','active','manual','unknown'))
  AND ("device_type" IS NULL OR "device_type" IN ('watch','phone','ring','scale','chest_strap','fitness_band','head_mounted','unknown'))
);

ALTER TABLE "wearable_resting_heart_rates" ADD CONSTRAINT "wearable_resting_heart_rates_valid" CHECK (
  "source" IN ('health_connect','simulated')
  AND length("external_id") BETWEEN 1 AND 200
  AND ("data_origin" IS NULL OR length("data_origin") BETWEEN 1 AND 200)
  AND "bpm" BETWEEN 20 AND 300
  AND "quality_status" IN ('device_reported','needs_review')
  AND ("recording_method" IS NULL OR "recording_method" IN ('automatic','active','manual','unknown'))
  AND ("device_type" IS NULL OR "device_type" IN ('watch','phone','ring','scale','chest_strap','fitness_band','head_mounted','unknown'))
);

ALTER TABLE "device_sync_checkpoints" ADD CONSTRAINT "device_sync_checkpoints_valid" CHECK (
  "source" IN ('health_connect','simulated')
  AND "metric" IN ('steps','heart_rate','resting_heart_rate','sleep','workouts','weight','glucose')
  AND ("cursor" IS NULL OR length("cursor") <= 64)
  AND ("last_error_code" IS NULL OR length("last_error_code") BETWEEN 1 AND 60)
);

ALTER TABLE "sleep_sessions" ADD CONSTRAINT "sleep_sessions_provenance_valid" CHECK (
  ("recording_method" IS NULL OR "recording_method" IN ('automatic','active','manual','unknown'))
  AND ("device_type" IS NULL OR "device_type" IN ('watch','phone','ring','scale','chest_strap','fitness_band','head_mounted','unknown'))
);

ALTER TABLE "daily_steps" DROP CONSTRAINT "daily_steps_valid";
ALTER TABLE "daily_steps" ADD CONSTRAINT "daily_steps_valid" CHECK (
  "source" IN ('health_connect','simulated') AND "steps" BETWEEN 0 AND 200000 AND "local_date" >= '2000-01-01'
);

ALTER TABLE "sleep_sessions" DROP CONSTRAINT "sleep_sessions_valid";
ALTER TABLE "sleep_sessions" ADD CONSTRAINT "sleep_sessions_valid" CHECK (
  "source" IN ('health_connect','simulated') AND "ended_at" > "started_at" AND "duration_minutes" BETWEEN 1 AND 1440
  AND length("external_id") BETWEEN 1 AND 200
);

ALTER TABLE "activity_sessions" DROP CONSTRAINT "activity_sessions_valid";
ALTER TABLE "activity_sessions" ADD CONSTRAINT "activity_sessions_valid" CHECK (
  activity_type IN ('walking','cycling','running','strength','other')
  AND source IN ('manual','health_connect','apple_health','simulated')
  AND quality_status IN ('user_reported','device_reported','needs_review')
  AND ((source = 'manual' AND external_id IS NULL AND quality_status <> 'device_reported')
    OR (source <> 'manual' AND external_id IS NOT NULL AND length(btrim(external_id)) BETWEEN 1 AND 200 AND quality_status <> 'user_reported'))
  AND reported_intensity IN ('unknown','light','moderate','vigorous')
  AND duration_minutes BETWEEN 1 AND 1440
  AND ended_at = started_at + duration_minutes * INTERVAL '1 minute'
  AND started_at >= '1900-01-01'::timestamptz
  AND (distance_km IS NULL OR distance_km BETWEEN 0 AND 1000)
  AND (steps IS NULL OR steps BETWEEN 0 AND 1000000)
  AND version > 0 AND length(create_hash) = 64 AND (notes IS NULL OR length(notes) <= 2000)
);
