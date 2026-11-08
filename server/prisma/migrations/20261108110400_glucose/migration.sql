-- AlterTable
ALTER TABLE "record_revisions" ADD COLUMN     "glucose_id" UUID,
ALTER COLUMN "meal_id" DROP NOT NULL;

-- CreateTable
CREATE TABLE "glucose_observations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'manual_glucometer',
    "source_record_id" TEXT,
    "measurement_type" TEXT NOT NULL DEFAULT 'capillary_blood',
    "value_mg_dl" DECIMAL(16,7) NOT NULL,
    "original_value" DECIMAL(12,4) NOT NULL,
    "original_unit" TEXT NOT NULL,
    "measured_at" TIMESTAMPTZ(6) NOT NULL,
    "recorded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "received_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "meal_context" TEXT NOT NULL DEFAULT 'unknown',
    "quality_status" TEXT NOT NULL DEFAULT 'user_reported',
    "quality_flags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "notes" TEXT,
    "version" INTEGER NOT NULL DEFAULT 1,
    "create_hash" TEXT NOT NULL,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "glucose_observations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "glucose_observations_user_id_measured_at_id_idx" ON "glucose_observations"("user_id", "measured_at" DESC, "id" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_glucose_id_version_key" ON "record_revisions"("glucose_id", "version");

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_glucose_id_fkey" FOREIGN KEY ("glucose_id") REFERENCES "glucose_observations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "glucose_observations" ADD CONSTRAINT "glucose_observations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE glucose_observations ALTER COLUMN quality_flags SET NOT NULL;
ALTER TABLE glucose_observations ADD CONSTRAINT glucose_observations_valid CHECK (
  source='manual_glucometer' AND measurement_type='capillary_blood' AND source_record_id IS NULL
  AND original_unit IN ('mg/dL','mmol/L') AND original_value > 0 AND value_mg_dl BETWEEN 1 AND 2000
  AND value_mg_dl=CASE original_unit WHEN 'mg/dL' THEN original_value ELSE original_value*18.016 END
  AND meal_context IN ('fasting','before_meal','after_meal','bedtime','other','unknown')
  AND quality_status IN ('user_reported','needs_review')
  AND quality_flags <@ ARRAY['user_flagged']::text[] AND cardinality(quality_flags)<=1
  AND ((quality_status='needs_review')=(cardinality(quality_flags)=1))
  AND version>0 AND length(create_hash)=64 AND measured_at>='1900-01-01'::timestamptz
  AND (notes IS NULL OR length(notes)<=2000)
);
ALTER TABLE record_revisions ADD CONSTRAINT record_revisions_one_source CHECK (num_nonnulls(meal_id,glucose_id)=1);
