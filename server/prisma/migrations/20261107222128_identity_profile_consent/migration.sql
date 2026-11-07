-- CreateTable
CREATE TABLE "user_profiles" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "birth_year" SMALLINT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "health_profiles" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "diagnosis_status" TEXT NOT NULL,
    "diabetes_type" TEXT,
    "diagnosed_year" SMALLINT,
    "treatment_context" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "data_source" TEXT NOT NULL DEFAULT 'user_reported',
    "eligibility_status" TEXT NOT NULL DEFAULT 'unknown',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "health_profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_settings" (
    "user_id" UUID NOT NULL,
    "locale" TEXT NOT NULL DEFAULT 'id-ID',
    "timezone" TEXT NOT NULL DEFAULT 'Asia/Jakarta',
    "glucose_unit" TEXT NOT NULL DEFAULT 'mg/dL',
    "text_size" TEXT NOT NULL DEFAULT 'system',
    "reduce_motion" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "user_settings_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "consent_records" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "purpose" TEXT NOT NULL,
    "policy_version" TEXT NOT NULL,
    "granted_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "withdrawn_at" TIMESTAMPTZ(6),
    "source" TEXT NOT NULL,

    CONSTRAINT "consent_records_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "onboarding_progress" (
    "user_id" UUID NOT NULL,
    "intro_seen_at" TIMESTAMPTZ(6),
    "completed_at" TIMESTAMPTZ(6),
    "version" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "onboarding_progress_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "audit_events" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "event_type" TEXT NOT NULL,
    "metadata" JSONB,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "user_profiles_user_id_key" ON "user_profiles"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "health_profiles_user_id_key" ON "health_profiles"("user_id");

-- CreateIndex
CREATE INDEX "consent_records_user_id_purpose_granted_at_idx" ON "consent_records"("user_id", "purpose", "granted_at" DESC);

-- CreateIndex
CREATE INDEX "audit_events_user_id_occurred_at_idx" ON "audit_events"("user_id", "occurred_at" DESC);

-- AddForeignKey
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "health_profiles" ADD CONSTRAINT "health_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_settings" ADD CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "onboarding_progress" ADD CONSTRAINT "onboarding_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_events" ADD CONSTRAINT "audit_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Invariants not expressible in the Prisma schema
ALTER TABLE "user_profiles"
  ADD CONSTRAINT "user_profiles_birth_year_range" CHECK ("birth_year" IS NULL OR "birth_year" BETWEEN 1900 AND 2100);

ALTER TABLE "health_profiles"
  ADD CONSTRAINT "health_profiles_diagnosis_status_valid" CHECK ("diagnosis_status" IN ('diagnosed', 'not_diagnosed', 'unknown', 'undisclosed')),
  ADD CONSTRAINT "health_profiles_diabetes_type_valid" CHECK ("diabetes_type" IS NULL OR "diabetes_type" IN ('type_2', 'type_1', 'other', 'unknown')),
  ADD CONSTRAINT "health_profiles_diagnosed_year_range" CHECK ("diagnosed_year" IS NULL OR "diagnosed_year" BETWEEN 1900 AND 2100),
  ADD CONSTRAINT "health_profiles_treatment_context_valid" CHECK ("treatment_context" <@ ARRAY['oral_medication', 'insulin', 'lifestyle', 'none', 'undisclosed']::TEXT[]),
  ADD CONSTRAINT "health_profiles_data_source_valid" CHECK ("data_source" IN ('user_reported')),
  ADD CONSTRAINT "health_profiles_eligibility_status_valid" CHECK ("eligibility_status" IN ('eligible', 'needs_review', 'unknown')),
  ADD CONSTRAINT "health_profiles_details_require_diagnosis" CHECK ("diagnosis_status" = 'diagnosed' OR ("diabetes_type" IS NULL AND "diagnosed_year" IS NULL));

ALTER TABLE "user_settings"
  ADD CONSTRAINT "user_settings_locale_valid" CHECK ("locale" IN ('id-ID', 'en-US')),
  ADD CONSTRAINT "user_settings_glucose_unit_valid" CHECK ("glucose_unit" IN ('mg/dL', 'mmol/L')),
  ADD CONSTRAINT "user_settings_text_size_valid" CHECK ("text_size" IN ('system', 'large', 'extra_large')),
  ADD CONSTRAINT "user_settings_timezone_length" CHECK (char_length("timezone") BETWEEN 1 AND 64);

ALTER TABLE "consent_records"
  ADD CONSTRAINT "consent_records_purpose_valid" CHECK ("purpose" IN ('health_data_processing', 'descriptive_summaries', 'product_analytics')),
  ADD CONSTRAINT "consent_records_source_valid" CHECK ("source" IN ('onboarding', 'settings', 'api')),
  ADD CONSTRAINT "consent_records_withdrawn_after_granted" CHECK ("withdrawn_at" IS NULL OR "withdrawn_at" >= "granted_at");

CREATE UNIQUE INDEX "consent_records_one_active_per_purpose" ON "consent_records"("user_id", "purpose") WHERE "withdrawn_at" IS NULL;

ALTER TABLE "onboarding_progress"
  ADD CONSTRAINT "onboarding_progress_version_non_negative" CHECK ("version" >= 0);
