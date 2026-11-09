-- AlterTable

-- AlterTable
ALTER TABLE "record_revisions" ADD COLUMN     "checkin_id" UUID,
ADD COLUMN     "goal_id" UUID,
ADD COLUMN     "intake_id" UUID,
ADD COLUMN     "regimen_id" UUID;

-- AlterTable

-- AlterTable

-- AlterTable

-- CreateTable
CREATE TABLE "medication_regimens" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "strength" TEXT,
    "dosage_form" TEXT,
    "dosing_instructions" TEXT,
    "instruction_source" TEXT NOT NULL DEFAULT 'user_reported',
    "start_date" DATE,
    "end_date" DATE,
    "status" TEXT NOT NULL DEFAULT 'active',
    "version" INTEGER NOT NULL DEFAULT 1,
    "create_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "medication_regimens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "medication_schedules" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "regimen_id" UUID NOT NULL,
    "local_time" TEXT NOT NULL,
    "timezone" TEXT NOT NULL,
    "days_of_week" INTEGER[],
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "effective_from" DATE NOT NULL,
    "disabled_at" TIMESTAMPTZ(6),
    "create_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "medication_schedules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "medication_intakes" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "regimen_id" UUID NOT NULL,
    "schedule_id" UUID,
    "scheduled_at" TIMESTAMPTZ(6),
    "taken_at" TIMESTAMPTZ(6),
    "event_at" TIMESTAMPTZ(6) NOT NULL,
    "status" TEXT NOT NULL,
    "medication_snapshot" JSONB NOT NULL,
    "notes" TEXT,
    "version" INTEGER NOT NULL DEFAULT 1,
    "create_hash" TEXT NOT NULL,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "medication_intakes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "behavior_goals" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "goal_type" TEXT NOT NULL,
    "target_value" DECIMAL(12,2) NOT NULL,
    "period" TEXT NOT NULL,
    "start_date" DATE NOT NULL,
    "end_date" DATE,
    "status" TEXT NOT NULL DEFAULT 'active',
    "version" INTEGER NOT NULL DEFAULT 1,
    "create_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "behavior_goals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "goal_checkins" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "goal_id" UUID NOT NULL,
    "event_at" TIMESTAMPTZ(6) NOT NULL,
    "status" TEXT NOT NULL,
    "value" DECIMAL(12,2) NOT NULL,
    "notes" TEXT,
    "version" INTEGER NOT NULL DEFAULT 1,
    "create_hash" TEXT NOT NULL,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "goal_checkins_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "medication_regimens_user_id_created_at_id_idx" ON "medication_regimens"("user_id", "created_at" DESC, "id" DESC);

-- CreateIndex
CREATE INDEX "medication_schedules_user_id_regimen_id_idx" ON "medication_schedules"("user_id", "regimen_id");

-- CreateIndex
CREATE INDEX "medication_intakes_user_id_event_at_id_idx" ON "medication_intakes"("user_id", "event_at" DESC, "id" DESC);

-- CreateIndex
CREATE INDEX "medication_intakes_regimen_id_event_at_idx" ON "medication_intakes"("regimen_id", "event_at" DESC);

-- CreateIndex
CREATE INDEX "behavior_goals_user_id_created_at_id_idx" ON "behavior_goals"("user_id", "created_at" DESC, "id" DESC);

-- CreateIndex
CREATE INDEX "goal_checkins_user_id_goal_id_event_at_id_idx" ON "goal_checkins"("user_id", "goal_id", "event_at" DESC, "id" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_regimen_id_version_key" ON "record_revisions"("regimen_id", "version");

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_intake_id_version_key" ON "record_revisions"("intake_id", "version");

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_goal_id_version_key" ON "record_revisions"("goal_id", "version");

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_checkin_id_version_key" ON "record_revisions"("checkin_id", "version");

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_regimen_id_fkey" FOREIGN KEY ("regimen_id") REFERENCES "medication_regimens"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_intake_id_fkey" FOREIGN KEY ("intake_id") REFERENCES "medication_intakes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_goal_id_fkey" FOREIGN KEY ("goal_id") REFERENCES "behavior_goals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_checkin_id_fkey" FOREIGN KEY ("checkin_id") REFERENCES "goal_checkins"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "medication_regimens" ADD CONSTRAINT "medication_regimens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "medication_schedules" ADD CONSTRAINT "medication_schedules_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "medication_schedules" ADD CONSTRAINT "medication_schedules_regimen_id_fkey" FOREIGN KEY ("regimen_id") REFERENCES "medication_regimens"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "medication_intakes" ADD CONSTRAINT "medication_intakes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "medication_intakes" ADD CONSTRAINT "medication_intakes_regimen_id_fkey" FOREIGN KEY ("regimen_id") REFERENCES "medication_regimens"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "medication_intakes" ADD CONSTRAINT "medication_intakes_schedule_id_fkey" FOREIGN KEY ("schedule_id") REFERENCES "medication_schedules"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "behavior_goals" ADD CONSTRAINT "behavior_goals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goal_checkins" ADD CONSTRAINT "goal_checkins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "goal_checkins" ADD CONSTRAINT "goal_checkins_goal_id_fkey" FOREIGN KEY ("goal_id") REFERENCES "behavior_goals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Invariants (explicit in SQL, like earlier domain migrations).
ALTER TABLE record_revisions DROP CONSTRAINT record_revisions_one_source;
ALTER TABLE record_revisions ADD CONSTRAINT record_revisions_one_source CHECK (num_nonnulls(meal_id,glucose_id,activity_id,regimen_id,intake_id,goal_id,checkin_id)=1);

ALTER TABLE medication_regimens ADD CONSTRAINT medication_regimens_valid CHECK (
 status IN ('active','paused','inactive')
 AND instruction_source IN ('user_reported','recorded_external_source')
 AND length(btrim(name)) BETWEEN 1 AND 120
 AND (end_date IS NULL OR start_date IS NULL OR end_date >= start_date));
ALTER TABLE medication_schedules ADD CONSTRAINT medication_schedules_valid CHECK (
 local_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
 AND cardinality(days_of_week) BETWEEN 1 AND 7
 AND days_of_week <@ ARRAY[1,2,3,4,5,6,7]);
ALTER TABLE medication_intakes ADD CONSTRAINT medication_intakes_valid CHECK (
 status IN ('taken','skipped','unknown')
 AND (status <> 'taken' OR taken_at IS NOT NULL)
 AND (status = 'taken' OR taken_at IS NULL));
-- One intake per scheduled occurrence (idempotent confirmation).
CREATE UNIQUE INDEX medication_intakes_occurrence_key ON medication_intakes(schedule_id, scheduled_at) WHERE schedule_id IS NOT NULL AND scheduled_at IS NOT NULL AND archived_at IS NULL;

ALTER TABLE behavior_goals ADD CONSTRAINT behavior_goals_valid CHECK (
 goal_type IN ('manual_checkins','activity_minutes','walking_sessions','record_meals','record_glucose')
 AND period IN ('daily','weekly')
 AND status IN ('active','paused','completed','archived')
 AND target_value > 0
 AND (end_date IS NULL OR end_date >= start_date));
ALTER TABLE goal_checkins ADD CONSTRAINT goal_checkins_valid CHECK (status IN ('completed','skipped','unknown') AND value > 0);

