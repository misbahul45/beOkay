-- AlterTable
ALTER TABLE "record_revisions" ADD COLUMN     "activity_id" UUID;

-- CreateTable
CREATE TABLE "activity_sessions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "activity_type" TEXT NOT NULL,
    "started_at" TIMESTAMPTZ(6) NOT NULL,
    "ended_at" TIMESTAMPTZ(6) NOT NULL,
    "duration_minutes" INTEGER NOT NULL,
    "distance_km" DECIMAL(10,3),
    "steps" INTEGER,
    "reported_intensity" TEXT NOT NULL DEFAULT 'unknown',
    "source" TEXT NOT NULL DEFAULT 'manual',
    "quality_status" TEXT NOT NULL DEFAULT 'user_reported',
    "notes" TEXT,
    "version" INTEGER NOT NULL DEFAULT 1,
    "create_hash" TEXT NOT NULL,
    "archived_at" TIMESTAMPTZ(6),
    "recorded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "received_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "activity_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "activity_sessions_user_id_started_at_id_idx" ON "activity_sessions"("user_id", "started_at" DESC, "id" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_activity_id_version_key" ON "record_revisions"("activity_id", "version");

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "activity_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "activity_sessions" ADD CONSTRAINT "activity_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE record_revisions DROP CONSTRAINT record_revisions_one_source;
ALTER TABLE record_revisions ADD CONSTRAINT record_revisions_one_source CHECK (num_nonnulls(meal_id,glucose_id,activity_id)=1);
ALTER TABLE activity_sessions ADD CONSTRAINT activity_sessions_valid CHECK (
 activity_type IN ('walking','cycling','running','strength','other')
 AND source='manual' AND quality_status IN ('user_reported','needs_review')
 AND reported_intensity IN ('unknown','light','moderate','vigorous')
 AND duration_minutes BETWEEN 1 AND 1440
 AND ended_at=started_at+duration_minutes*INTERVAL '1 minute'
 AND started_at>='1900-01-01'::timestamptz
 AND (distance_km IS NULL OR distance_km BETWEEN 0 AND 1000)
 AND (steps IS NULL OR steps BETWEEN 0 AND 1000000)
 AND version>0 AND length(create_hash)=64 AND (notes IS NULL OR length(notes)<=2000)
);
