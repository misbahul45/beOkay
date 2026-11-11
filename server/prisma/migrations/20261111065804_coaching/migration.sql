-- CreateTable
CREATE TABLE "coaching_actions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "opportunity_key" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "rationale" TEXT NOT NULL,
    "evidence" JSONB NOT NULL,
    "params" JSONB NOT NULL,
    "slot" TEXT,
    "start_date" DATE NOT NULL,
    "days" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PROPOSED',
    "close_reason" TEXT,
    "reminder_id" UUID,
    "policy_version" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "decided_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "coaching_actions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "coaching_outcomes" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "action_id" UUID NOT NULL,
    "local_date" DATE NOT NULL,
    "status" TEXT NOT NULL,
    "evidence_type" TEXT,
    "evidence_id" UUID,
    "observed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "coaching_outcomes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "coaching_events" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "action_id" UUID,
    "operation_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "detail" JSONB,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "coaching_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "weekly_checkins" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "week_start" DATE NOT NULL,
    "operation_id" UUID NOT NULL,
    "mood" TEXT,
    "hardest" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "note" TEXT,
    "preferred_slot" TEXT,
    "adjustments" JSONB NOT NULL DEFAULT '[]',
    "summary" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "weekly_checkins_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "coaching_actions_user_id_status_created_at_idx" ON "coaching_actions"("user_id", "status", "created_at" DESC);

-- CreateIndex
CREATE INDEX "coaching_outcomes_user_id_local_date_idx" ON "coaching_outcomes"("user_id", "local_date");

-- CreateIndex
CREATE UNIQUE INDEX "coaching_outcomes_action_id_local_date_key" ON "coaching_outcomes"("action_id", "local_date");

-- CreateIndex
CREATE INDEX "coaching_events_action_id_idx" ON "coaching_events"("action_id");

-- CreateIndex
CREATE UNIQUE INDEX "coaching_events_user_id_operation_id_key" ON "coaching_events"("user_id", "operation_id");

-- CreateIndex
CREATE UNIQUE INDEX "weekly_checkins_user_id_week_start_key" ON "weekly_checkins"("user_id", "week_start");

-- CreateIndex
CREATE UNIQUE INDEX "weekly_checkins_user_id_operation_id_key" ON "weekly_checkins"("user_id", "operation_id");

-- AddForeignKey
ALTER TABLE "coaching_actions" ADD CONSTRAINT "coaching_actions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "coaching_actions" ADD CONSTRAINT "coaching_actions_reminder_id_fkey" FOREIGN KEY ("reminder_id") REFERENCES "reminders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "coaching_outcomes" ADD CONSTRAINT "coaching_outcomes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "coaching_outcomes" ADD CONSTRAINT "coaching_outcomes_action_id_fkey" FOREIGN KEY ("action_id") REFERENCES "coaching_actions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "coaching_events" ADD CONSTRAINT "coaching_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "coaching_events" ADD CONSTRAINT "coaching_events_action_id_fkey" FOREIGN KEY ("action_id") REFERENCES "coaching_actions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "weekly_checkins" ADD CONSTRAINT "weekly_checkins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "coaching_actions" ADD CONSTRAINT "coaching_actions_valid"
  CHECK (
    "source" IN ('MEAL_LOG_GAP','ACTIVITY_STEP_DOWN','GOAL_PACE','ROUTINE_START')
    AND "kind" IN ('ACTIVITY_SESSION','MEAL_LOGGING')
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
CREATE UNIQUE INDEX "coaching_actions_open_proposal_key" ON "coaching_actions"("user_id", "opportunity_key") WHERE "status" = 'PROPOSED';

ALTER TABLE "coaching_outcomes" ADD CONSTRAINT "coaching_outcomes_valid"
  CHECK (
    "status" IN ('OBSERVED','USER_CONFIRMED','RETRACTED')
    AND ("evidence_type" IS NULL OR "evidence_type" IN ('activity_session','meal_log'))
    AND (("status" = 'OBSERVED') = ("evidence_id" IS NOT NULL AND "evidence_type" IS NOT NULL))
    AND ("status" <> 'OBSERVED' OR "observed_at" IS NOT NULL)
  );

ALTER TABLE "coaching_events" ADD CONSTRAINT "coaching_events_valid"
  CHECK (
    "type" IN ('DECISION','FEEDBACK','CONFIRMATION')
    AND length("value") BETWEEN 1 AND 40
    AND ("detail" IS NULL OR jsonb_typeof("detail") = 'object')
  );

ALTER TABLE "weekly_checkins" ADD CONSTRAINT "weekly_checkins_valid"
  CHECK (
    ("mood" IS NULL OR "mood" IN ('GOOD','MIXED','HARD'))
    AND "hardest" <@ ARRAY['TIME','FORGOT','ENERGY','MOTIVATION','OTHER']::TEXT[]
    AND ("note" IS NULL OR length("note") BETWEEN 1 AND 280)
    AND ("preferred_slot" IS NULL OR "preferred_slot" IN ('MORNING','MIDDAY','AFTERNOON','EVENING'))
    AND jsonb_typeof("adjustments") = 'array'
    AND jsonb_typeof("summary") = 'object'
  );

ALTER TABLE "intervention_decisions" DROP CONSTRAINT "intervention_decisions_valid";
ALTER TABLE "intervention_decisions" ADD CONSTRAINT "intervention_decisions_valid" CHECK (
  "trigger_type" IN ('USER_REQUESTS_SUPPORT','GOAL_WINDOW_APPROACHING','USER_SELECTED_ROUTINE_REMINDER','WEEKLY_REVIEW_AVAILABLE','COACHING_ACTION_DUE')
  AND "option" IN ('NO_INTERVENTION','IN_APP_SUGGESTION','GOAL_REVIEW_CARD','WEEKLY_REFLECTION','ACTION_REMINDER_CARD','CLARIFICATION_QUESTION')
  AND "eligibility_status" IN ('ELIGIBLE','BLOCKED')
  AND "data_coverage" IN ('FULL','PARTIAL','NONE')
  AND "delivery_status" IN ('NOT_APPLICABLE','ELIGIBLE','DELIVERED','OPENED','SNOOZED','RESPONDED','EXPIRED','CANCELLED')
  AND "approval_status" IN ('NOT_REQUIRED','USER_INITIATED')
  AND ("response" IS NULL OR "response" IN ('USEFUL','NOT_USEFUL','NOT_NOW','TOO_FREQUENT','ALREADY_DONE','DISMISSED','STOP_THIS_TYPE'))
  AND (("option" = 'NO_INTERVENTION') = ("delivery_status" = 'NOT_APPLICABLE'))
  AND ("option" <> 'NO_INTERVENTION' OR "reason" IS NOT NULL)
);
