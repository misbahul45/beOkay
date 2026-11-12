-- AlterTable
ALTER TABLE "memory_items" ADD COLUMN     "expires_at" TIMESTAMPTZ(6);

-- CreateTable
CREATE TABLE "router_proposals" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "message_id" UUID,
    "router_version" TEXT NOT NULL,
    "proposed_route" TEXT,
    "args" JSONB NOT NULL DEFAULT '{}',
    "confidence" DECIMAL(4,3),
    "decision" TEXT NOT NULL,
    "reject_reason" TEXT,
    "judge_verdict" TEXT,
    "judge_category" TEXT,
    "memory_kind" TEXT,
    "model" TEXT,
    "latency_ms" INTEGER,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "router_proposals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "weekly_episodes" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "week_start" DATE NOT NULL,
    "summary" JSONB NOT NULL,
    "lines" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "version" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "weekly_episodes_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "router_proposals_user_id_created_at_idx" ON "router_proposals"("user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "router_proposals_decision_created_at_idx" ON "router_proposals"("decision", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "weekly_episodes_user_id_week_start_key" ON "weekly_episodes"("user_id", "week_start");

-- AddForeignKey
ALTER TABLE "router_proposals" ADD CONSTRAINT "router_proposals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "weekly_episodes" ADD CONSTRAINT "weekly_episodes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "router_proposals" ADD CONSTRAINT "router_proposals_valid" CHECK (
  "decision" IN ('ACCEPTED','REJECTED','HELD','ERROR')
  AND ("proposed_route" IS NULL OR "proposed_route" IN ('GREETING','THANKS','SUPPORT','REFLECTION','COMMUNITY','HELP','STATS','ACTIVITY_PLAN','FOOD','CLARIFY_FOOD','PREFERENCE','UNKNOWN'))
  AND ("judge_verdict" IS NULL OR "judge_verdict" IN ('SAFE','HOLD'))
  AND ("judge_category" IS NULL OR "judge_category" IN ('MEDICAL_ADVICE','URGENT','SELF_HARM','INJECTION','OTHER'))
  AND ("memory_kind" IS NULL OR "memory_kind" IN ('FOOD_CONTEXT','BARRIER','HEALTH_EVENT'))
  AND ("reject_reason" IS NULL OR length("reject_reason") BETWEEN 1 AND 60)
  AND jsonb_typeof("args") = 'object'
  AND length("args"::text) <= 400
  AND ("confidence" IS NULL OR "confidence" BETWEEN 0 AND 1)
  AND ("latency_ms" IS NULL OR "latency_ms" >= 0)
);

ALTER TABLE "weekly_episodes" ADD CONSTRAINT "weekly_episodes_valid" CHECK (
  jsonb_typeof("summary") = 'object' AND cardinality("lines") <= 6 AND length("version") BETWEEN 1 AND 40
);

ALTER TABLE "memory_items" DROP CONSTRAINT "memory_items_valid";
ALTER TABLE "memory_items" ADD CONSTRAINT "memory_items_valid"
  CHECK (
    "category" IN ('PREFERENCE','EPISODIC')
    AND "kind" IN ('ACTIVITY_TIME','SCHEDULE','ACTIVITY_LIKE','ACTIVITY_DISLIKE','AVAILABLE_MINUTES','FOOD_CONTEXT','BARRIER','HEALTH_EVENT')
    AND "status" IN ('PROPOSED','ACTIVE','DISMISSED')
    AND "source_type" IN ('CONVERSATION','USER','LANGUAGE_MODEL')
    AND "confidence" IN ('STATED','INFERRED')
    AND "sensitivity" IN ('LOW','MEDIUM')
    AND "retention" IN ('UNTIL_DELETED','EXPIRES')
    AND length("content") BETWEEN 1 AND 160
    AND length("key") BETWEEN 1 AND 120
    AND "version" >= 1
    AND ("status" <> 'ACTIVE' OR "confirmed_at" IS NOT NULL)
    AND (("retention" = 'EXPIRES') = ("expires_at" IS NOT NULL))
  );

ALTER TABLE "consent_records" DROP CONSTRAINT "consent_records_purpose_valid";
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_purpose_valid"
  CHECK ("purpose" IN ('health_data_processing','descriptive_summaries','product_analytics','personalized_ai','community_membership','challenge_participation','leaderboard_visibility','model_inference','ai_text_generation','ai_message_understanding'));

ALTER TABLE "feature_flags" DROP CONSTRAINT "feature_flags_valid";
ALTER TABLE "feature_flags" ADD CONSTRAINT "feature_flags_valid" CHECK (
  "key" IN ('assistant','conversation','coaching','community','ml_inference','food_vision','web_discovery','analytics','push','llm_router')
  AND ("note" IS NULL OR length("note") <= 300)
  AND length("updated_by") BETWEEN 1 AND 120
);

UPDATE "model_versions" SET "status" = 'DEPRECATED', "approval_note" = 'Dihentikan 3.0 Fase 10 (A-8): kelas tidak relevan untuk hidangan Indonesia dan lisensi dataset tidak jelas.' WHERE "model_key" = 'dish-classifier' AND "status" <> 'DEPRECATED';

