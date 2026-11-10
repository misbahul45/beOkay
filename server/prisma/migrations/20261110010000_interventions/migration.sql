-- Mesin intervensi (JITAI) tahap awal: pengaturan pengguna dan log keputusan. Tidak ada kolom nilai klinis.
CREATE TABLE "intervention_preferences" (
    "user_id" UUID NOT NULL,
    "paused_until" TIMESTAMPTZ(6),
    "quiet_start_minute" INTEGER NOT NULL DEFAULT 1320,
    "quiet_end_minute" INTEGER NOT NULL DEFAULT 420,
    "max_per_day" INTEGER NOT NULL DEFAULT 2,
    "max_per_week" INTEGER NOT NULL DEFAULT 7,
    "muted_triggers" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "intervention_preferences_pkey" PRIMARY KEY ("user_id"),
    CONSTRAINT "intervention_preferences_valid" CHECK ("quiet_start_minute" BETWEEN 0 AND 1439 AND "quiet_end_minute" BETWEEN 0 AND 1439 AND "max_per_day" BETWEEN 0 AND 5 AND "max_per_week" BETWEEN 0 AND 21)
);
ALTER TABLE "intervention_preferences" ADD CONSTRAINT "intervention_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "intervention_decisions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "trigger_type" TEXT NOT NULL,
    "subject_ref" TEXT,
    "decided_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "local_date" TEXT NOT NULL,
    "timezone" TEXT NOT NULL,
    "policy_version" TEXT NOT NULL,
    "eligibility_status" TEXT NOT NULL,
    "data_coverage" TEXT NOT NULL,
    "option" TEXT NOT NULL,
    "reason" TEXT,
    "approval_status" TEXT NOT NULL,
    "delivery_status" TEXT NOT NULL,
    "content" JSONB,
    "dedupe_key" TEXT,
    "expires_at" TIMESTAMPTZ(6),
    "snoozed_until" TIMESTAMPTZ(6),
    "response" TEXT,
    "responded_at" TIMESTAMPTZ(6),
    CONSTRAINT "intervention_decisions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "intervention_decisions_valid" CHECK (
      "trigger_type" IN ('USER_REQUESTS_SUPPORT','GOAL_WINDOW_APPROACHING','USER_SELECTED_ROUTINE_REMINDER','WEEKLY_REVIEW_AVAILABLE')
      AND "option" IN ('NO_INTERVENTION','IN_APP_SUGGESTION','GOAL_REVIEW_CARD','WEEKLY_REFLECTION')
      AND "eligibility_status" IN ('ELIGIBLE','BLOCKED')
      AND "data_coverage" IN ('FULL','PARTIAL','NONE')
      AND "delivery_status" IN ('NOT_APPLICABLE','ELIGIBLE','DELIVERED','OPENED','SNOOZED','RESPONDED','EXPIRED','CANCELLED')
      AND "approval_status" IN ('NOT_REQUIRED','USER_INITIATED')
      AND ("response" IS NULL OR "response" IN ('USEFUL','NOT_USEFUL','NOT_NOW','TOO_FREQUENT','ALREADY_DONE','DISMISSED','STOP_THIS_TYPE'))
      AND (("option" = 'NO_INTERVENTION') = ("delivery_status" = 'NOT_APPLICABLE'))
      AND ("option" <> 'NO_INTERVENTION' OR "reason" IS NOT NULL)
    )
);
CREATE UNIQUE INDEX "intervention_decisions_dedupe_key_key" ON "intervention_decisions"("dedupe_key");
CREATE INDEX "intervention_decisions_user_id_decided_at_idx" ON "intervention_decisions"("user_id", "decided_at" DESC);
CREATE INDEX "intervention_decisions_user_id_delivery_status_idx" ON "intervention_decisions"("user_id", "delivery_status");
ALTER TABLE "intervention_decisions" ADD CONSTRAINT "intervention_decisions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
