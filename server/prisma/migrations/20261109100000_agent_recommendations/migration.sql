-- Runtime agen (state machine di Postgres), rekomendasi, rencana makan, umpan balik, dan personalisasi deterministik.
-- Semua baris milik akun (ON DELETE CASCADE). Rencana makan BUKAN konsumsi. Keputusan pengguna idempoten lewat (user_id, operation_id).
CREATE TABLE "agent_runs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "status" TEXT NOT NULL,
    "intent" TEXT NOT NULL,
    "input_text" TEXT NOT NULL,
    "idempotency_key" TEXT NOT NULL,
    "state" JSONB NOT NULL DEFAULT '{}',
    "safety_decision" TEXT,
    "tool_calls_used" INTEGER NOT NULL DEFAULT 0,
    "version" INTEGER NOT NULL DEFAULT 1,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "agent_runs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "agent_runs_valid" CHECK (
        "status" IN ('CREATED','VALIDATING','RUNNING','WAITING_FOR_USER','COMPLETED','BLOCKED','FAILED','CANCELLED','EXPIRED')
        AND length("input_text") BETWEEN 1 AND 2000 AND length("idempotency_key") BETWEEN 8 AND 100
        AND "tool_calls_used" BETWEEN 0 AND 100 AND "version" >= 1)
);
CREATE UNIQUE INDEX "agent_runs_user_id_idempotency_key_key" ON "agent_runs"("user_id", "idempotency_key");
CREATE INDEX "agent_runs_user_id_created_at_idx" ON "agent_runs"("user_id", "created_at" DESC);
ALTER TABLE "agent_runs" ADD CONSTRAINT "agent_runs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "agent_run_events" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "run_id" UUID NOT NULL,
    "seq" INTEGER NOT NULL,
    "type" TEXT NOT NULL,
    "payload" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "agent_run_events_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "agent_run_events_valid" CHECK ("seq" >= 1 AND length("type") BETWEEN 1 AND 60)
);
CREATE UNIQUE INDEX "agent_run_events_run_id_seq_key" ON "agent_run_events"("run_id", "seq");
ALTER TABLE "agent_run_events" ADD CONSTRAINT "agent_run_events_run_id_fkey" FOREIGN KEY ("run_id") REFERENCES "agent_runs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "agent_tool_calls" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "run_id" UUID NOT NULL,
    "tool" TEXT NOT NULL,
    "tool_version" TEXT NOT NULL,
    "args_hash" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "error_code" TEXT,
    "duration_ms" INTEGER NOT NULL,
    "result_size" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "agent_tool_calls_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "agent_tool_calls_valid" CHECK ("status" IN ('OK','ERROR','DENIED','TIMEOUT') AND length("args_hash") = 64)
);
CREATE INDEX "agent_tool_calls_run_id_idx" ON "agent_tool_calls"("run_id");
ALTER TABLE "agent_tool_calls" ADD CONSTRAINT "agent_tool_calls_run_id_fkey" FOREIGN KEY ("run_id") REFERENCES "agent_runs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "recommendations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "run_id" UUID NOT NULL,
    "rec_type" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "payload" JSONB NOT NULL,
    "policy_version" TEXT NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "decided_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "recommendations_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "recommendations_valid" CHECK ("rec_type" IN ('NUTRITION','ACTIVITY','BEHAVIOR') AND "status" IN ('OFFERED','ACCEPTED','REJECTED','EXPIRED','INVALIDATED') AND "version" >= 1)
);
CREATE INDEX "recommendations_user_id_created_at_idx" ON "recommendations"("user_id", "created_at" DESC);
CREATE INDEX "recommendations_run_id_idx" ON "recommendations"("run_id");
ALTER TABLE "recommendations" ADD CONSTRAINT "recommendations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "recommendations" ADD CONSTRAINT "recommendations_run_id_fkey" FOREIGN KEY ("run_id") REFERENCES "agent_runs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "recommendation_decisions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "recommendation_id" UUID NOT NULL,
    "operation_id" UUID NOT NULL,
    "decision" TEXT NOT NULL,
    "result_version" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "recommendation_decisions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "recommendation_decisions_valid" CHECK ("decision" IN ('ACCEPT','REJECT'))
);
CREATE UNIQUE INDEX "recommendation_decisions_user_id_operation_id_key" ON "recommendation_decisions"("user_id", "operation_id");
ALTER TABLE "recommendation_decisions" ADD CONSTRAINT "recommendation_decisions_recommendation_id_fkey" FOREIGN KEY ("recommendation_id") REFERENCES "recommendations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "recommendation_feedback" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "recommendation_id" UUID NOT NULL,
    "operation_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "recommendation_feedback_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "recommendation_feedback_valid" CHECK ("kind" IN ('CONSUMED','NOT_CONSUMED'))
);
CREATE UNIQUE INDEX "recommendation_feedback_user_id_operation_id_key" ON "recommendation_feedback"("user_id", "operation_id");
CREATE INDEX "recommendation_feedback_recommendation_id_idx" ON "recommendation_feedback"("recommendation_id");
ALTER TABLE "recommendation_feedback" ADD CONSTRAINT "recommendation_feedback_recommendation_id_fkey" FOREIGN KEY ("recommendation_id") REFERENCES "recommendations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "planned_meals" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "recommendation_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "source_ref" TEXT,
    "per100g" JSONB NOT NULL,
    "status" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "planned_meals_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "planned_meals_valid" CHECK ("status" IN ('PLANNED','CONSUMED','SKIPPED','CANCELLED') AND length(btrim("name")) BETWEEN 1 AND 200 AND "version" >= 1)
);
CREATE UNIQUE INDEX "planned_meals_recommendation_id_key" ON "planned_meals"("recommendation_id");
CREATE INDEX "planned_meals_user_id_created_at_idx" ON "planned_meals"("user_id", "created_at" DESC);
ALTER TABLE "planned_meals" ADD CONSTRAINT "planned_meals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "planned_meals" ADD CONSTRAINT "planned_meals_recommendation_id_fkey" FOREIGN KEY ("recommendation_id") REFERENCES "recommendations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "personalization_profiles" (
    "user_id" UUID NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 0,
    "data" JSONB NOT NULL DEFAULT '{}',
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "personalization_profiles_pkey" PRIMARY KEY ("user_id"),
    CONSTRAINT "personalization_profiles_valid" CHECK ("version" >= 0)
);
ALTER TABLE "personalization_profiles" ADD CONSTRAINT "personalization_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "personalization_events" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "version" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "source_recommendation_id" UUID,
    "change" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "personalization_events_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "personalization_events_user_id_version_key" ON "personalization_events"("user_id", "version");
ALTER TABLE "personalization_events" ADD CONSTRAINT "personalization_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "personalization_profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;
