-- AlterTable
ALTER TABLE "record_revisions" ADD COLUMN     "lab_id" UUID,
ADD COLUMN     "vital_id" UUID;

-- CreateTable
CREATE TABLE "usage_events" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "event_type" TEXT NOT NULL,
    "domain" TEXT,
    "meta" JSONB NOT NULL DEFAULT '{}',
    "app_version" TEXT,
    "platform" TEXT,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "usage_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "vital_measurements" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "value" DECIMAL(10,3) NOT NULL,
    "value2" DECIMAL(10,3),
    "unit" TEXT NOT NULL,
    "measured_at" TIMESTAMPTZ(6) NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'manual',
    "notes" TEXT,
    "create_hash" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "vital_measurements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "lab_results" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "test" TEXT NOT NULL,
    "value" DECIMAL(10,3) NOT NULL,
    "unit" TEXT NOT NULL,
    "sampled_at" DATE NOT NULL,
    "lab_name" TEXT,
    "source" TEXT NOT NULL DEFAULT 'manual',
    "notes" TEXT,
    "create_hash" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "lab_results_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "feature_flags" (
    "key" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL,
    "note" TEXT,
    "updated_by" TEXT NOT NULL,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "feature_flags_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "incident_reports" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "category" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "app_version" TEXT,
    "contact_ok" BOOLEAN NOT NULL DEFAULT false,
    "emailed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "incident_reports_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "usage_events_user_id_occurred_at_idx" ON "usage_events"("user_id", "occurred_at" DESC);

-- CreateIndex
CREATE INDEX "usage_events_event_type_occurred_at_idx" ON "usage_events"("event_type", "occurred_at" DESC);

-- CreateIndex
CREATE INDEX "vital_measurements_user_id_kind_measured_at_idx" ON "vital_measurements"("user_id", "kind", "measured_at" DESC);

-- CreateIndex
CREATE INDEX "lab_results_user_id_test_sampled_at_idx" ON "lab_results"("user_id", "test", "sampled_at" DESC);

-- CreateIndex
CREATE INDEX "incident_reports_created_at_idx" ON "incident_reports"("created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_vital_id_version_key" ON "record_revisions"("vital_id", "version");

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_lab_id_version_key" ON "record_revisions"("lab_id", "version");

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_vital_id_fkey" FOREIGN KEY ("vital_id") REFERENCES "vital_measurements"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_lab_id_fkey" FOREIGN KEY ("lab_id") REFERENCES "lab_results"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "usage_events" ADD CONSTRAINT "usage_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vital_measurements" ADD CONSTRAINT "vital_measurements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lab_results" ADD CONSTRAINT "lab_results_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "incident_reports" ADD CONSTRAINT "incident_reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;


ALTER TABLE "usage_events" ADD CONSTRAINT "usage_events_valid" CHECK (
  "event_type" IN ('record_created','screen_opened','suggestion_offered','suggestion_accepted','suggestion_declined','notification_opened','quick_repeat_used','context_viewed','reflection_completed','strategy_chosen','vital_recorded','lab_recorded','form_saved')
  AND ("domain" IS NULL OR "domain" IN ('meal','glucose','activity','medication','goal','vital','lab','coaching','assistant','community','notification','home','insights','settings','other'))
  AND jsonb_typeof("meta") = 'object'
  AND length("meta"::text) <= 400
  AND ("app_version" IS NULL OR length("app_version") BETWEEN 1 AND 40)
  AND ("platform" IS NULL OR "platform" IN ('android','ios','server'))
);

ALTER TABLE "vital_measurements" ADD CONSTRAINT "vital_measurements_valid" CHECK (
  "kind" IN ('weight','height','waist','blood_pressure')
  AND "source" IN ('manual','health_connect')
  AND "version" >= 1
  AND ("kind" <> 'weight' OR ("unit" = 'kg' AND "value" BETWEEN 10 AND 500 AND "value2" IS NULL))
  AND ("kind" <> 'height' OR ("unit" = 'cm' AND "value" BETWEEN 50 AND 250 AND "value2" IS NULL))
  AND ("kind" <> 'waist' OR ("unit" = 'cm' AND "value" BETWEEN 30 AND 300 AND "value2" IS NULL))
  AND ("kind" <> 'blood_pressure' OR ("unit" = 'mmHg' AND "value" BETWEEN 40 AND 300 AND "value2" BETWEEN 20 AND 200 AND "value" > "value2"))
  AND ("notes" IS NULL OR length("notes") <= 2000)
);

ALTER TABLE "lab_results" ADD CONSTRAINT "lab_results_valid" CHECK (
  "test" IN ('hba1c','fasting_glucose','ldl','hdl','total_cholesterol','triglycerides','creatinine','egfr','urine_acr')
  AND "source" IN ('manual','lab_report')
  AND "version" >= 1
  AND "value" > 0 AND "value" < 100000
  AND ("test" <> 'hba1c' OR ("unit" = '%' AND "value" BETWEEN 2 AND 25) OR ("unit" = 'mmol/mol' AND "value" BETWEEN 1 AND 300))
  AND ("test" NOT IN ('fasting_glucose','ldl','hdl','total_cholesterol','triglycerides') OR "unit" IN ('mg/dL','mmol/L'))
  AND ("test" <> 'creatinine' OR "unit" IN ('mg/dL','umol/L'))
  AND ("test" <> 'egfr' OR "unit" = 'mL/min/1.73m2')
  AND ("test" <> 'urine_acr' OR "unit" IN ('mg/g','mg/mmol'))
  AND ("lab_name" IS NULL OR length("lab_name") BETWEEN 1 AND 120)
  AND ("notes" IS NULL OR length("notes") <= 2000)
);

ALTER TABLE "feature_flags" ADD CONSTRAINT "feature_flags_valid" CHECK (
  "key" IN ('assistant','conversation','coaching','community','ml_inference','food_vision','web_discovery','analytics','push')
  AND ("note" IS NULL OR length("note") <= 300)
  AND length("updated_by") BETWEEN 1 AND 120
);

ALTER TABLE "incident_reports" ADD CONSTRAINT "incident_reports_valid" CHECK (
  "category" IN ('bug','adverse_event','privacy','other')
  AND length("message") BETWEEN 1 AND 2000
  AND ("app_version" IS NULL OR length("app_version") BETWEEN 1 AND 40)
);

ALTER TABLE record_revisions DROP CONSTRAINT record_revisions_one_source;
ALTER TABLE record_revisions ADD CONSTRAINT record_revisions_one_source CHECK (num_nonnulls(meal_id,glucose_id,activity_id,regimen_id,intake_id,goal_id,checkin_id,vital_id,lab_id)=1);

ALTER TABLE "coaching_actions" DROP CONSTRAINT "coaching_actions_valid";
ALTER TABLE "coaching_actions" ADD CONSTRAINT "coaching_actions_valid"
  CHECK (
    "source" IN ('MEAL_LOG_GAP','ACTIVITY_STEP_DOWN','GOAL_PACE','ROUTINE_START','PROBLEM_SOLVING')
    AND "kind" IN ('ACTIVITY_SESSION','MEAL_LOGGING','HABIT_STEP')
    AND "status" IN ('PROPOSED','ACCEPTED','DECLINED','EXPIRED','WITHDRAWN')
    AND ("slot" IS NULL OR "slot" IN ('MORNING','MIDDAY','AFTERNOON','EVENING'))
    AND "days" BETWEEN 1 AND 7
    AND "version" >= 1
    AND jsonb_typeof("evidence") = 'object'
    AND jsonb_typeof("params") = 'object'
    AND length("title") BETWEEN 1 AND 120
    AND length("rationale") BETWEEN 1 AND 400
    AND length("opportunity_key") BETWEEN 1 AND 200
    AND (("status" = 'PROPOSED') = ("decided_at" IS NULL))
    AND ("close_reason" IS NULL OR "status" IN ('DECLINED','EXPIRED','WITHDRAWN'))
  );

ALTER TABLE "sync_operations" DROP CONSTRAINT "sync_operations_valid";
ALTER TABLE "sync_operations" ADD CONSTRAINT "sync_operations_valid" CHECK (
  "domain" IN ('meal','glucose','activity','medication_intake','goal_checkin','vital','lab')
  AND "operation_type" IN ('create','update')
  AND "status" IN ('SYNCED','CONFLICT','NEEDS_REVIEW','SYNC_FAILED')
);

ALTER TABLE "notifications" DROP CONSTRAINT "notifications_valid";
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_valid" CHECK (
  "kind" IN ('REMINDER','COACHING','REFLECTION','CHALLENGE','RECOGNITION','LAB_REMINDER')
  AND length("title") BETWEEN 1 AND 80
  AND length("body") BETWEEN 1 AND 240
  AND "action" IN ('OPEN_HOME','OPEN_LOG','OPEN_COACHING','OPEN_REFLECTION','OPEN_CHALLENGE','OPEN_COMMUNITY','OPEN_RECOGNITIONS','OPEN_REMINDERS','OPEN_GOALS','OPEN_MEDICATIONS','OPEN_CLINICAL')
  AND length("dedupe_key") BETWEEN 1 AND 200
);

ALTER TABLE "notification_preferences" DROP CONSTRAINT "notification_preferences_valid";
ALTER TABLE "notification_preferences" ADD CONSTRAINT "notification_preferences_valid" CHECK (
  "muted_kinds" <@ ARRAY['REMINDER','COACHING','REFLECTION','CHALLENGE','RECOGNITION','LAB_REMINDER']::TEXT[]
);
