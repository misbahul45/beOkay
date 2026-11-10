-- Rencana aktivitas dari rekomendasi yang diterima. BUKAN sesi: sesi tetap dicatat pengguna (atau diimpor) terpisah.
CREATE TABLE "activity_plans" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "recommendation_id" UUID NOT NULL,
    "activity_type" TEXT NOT NULL,
    "duration_minutes" INTEGER NOT NULL,
    "planned_for" DATE NOT NULL,
    "status" TEXT NOT NULL,
    "linked_session_id" UUID,
    "version" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "activity_plans_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "activity_plans_valid" CHECK (
        "status" IN ('CONFIRMED','IN_PROGRESS','COMPLETED','SKIPPED','CANCELLED','NEEDS_REVIEW')
        AND "activity_type" IN ('walking','cycling','running','strength','other')
        AND "duration_minutes" BETWEEN 5 AND 90 AND "version" >= 1)
);
CREATE UNIQUE INDEX "activity_plans_recommendation_id_key" ON "activity_plans"("recommendation_id");
CREATE INDEX "activity_plans_user_id_created_at_idx" ON "activity_plans"("user_id", "created_at" DESC);
ALTER TABLE "activity_plans" ADD CONSTRAINT "activity_plans_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "activity_plans" ADD CONSTRAINT "activity_plans_recommendation_id_fkey" FOREIGN KEY ("recommendation_id") REFERENCES "recommendations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "activity_plans" ADD CONSTRAINT "activity_plans_linked_session_id_fkey" FOREIGN KEY ("linked_session_id") REFERENCES "activity_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "recommendation_feedback" DROP CONSTRAINT "recommendation_feedback_valid";
ALTER TABLE "recommendation_feedback" ADD CONSTRAINT "recommendation_feedback_valid" CHECK ("kind" IN ('CONSUMED','NOT_CONSUMED','COMPLETED','SKIPPED'));
