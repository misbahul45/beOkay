-- Impor aktivitas dari perangkat (Health Connect / Apple Health). Sesi impor membawa external_id untuk dedup,
-- berstatus device_reported (bukan user_reported), dan yang bertabrakan waktu dengan catatan lain masuk needs_review.
ALTER TABLE "activity_sessions" ADD COLUMN "external_id" TEXT;
CREATE UNIQUE INDEX "activity_sessions_user_id_source_external_id_key" ON "activity_sessions"("user_id", "source", "external_id");
ALTER TABLE "activity_sessions" DROP CONSTRAINT "activity_sessions_valid";
ALTER TABLE "activity_sessions" ADD CONSTRAINT "activity_sessions_valid" CHECK (
  activity_type IN ('walking','cycling','running','strength','other')
  AND source IN ('manual','health_connect','apple_health')
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
