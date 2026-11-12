-- CreateTable
CREATE TABLE "job_runs" (
    "name" TEXT NOT NULL,
    "last_started_at" TIMESTAMPTZ(6),
    "last_finished_at" TIMESTAMPTZ(6),
    "last_status" TEXT,
    "last_result" JSONB,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "job_runs_pkey" PRIMARY KEY ("name")
);

ALTER TABLE "job_runs" ADD CONSTRAINT "job_runs_valid" CHECK (
  "name" ~ '^[a-z][a-z_]{2,39}$'
  AND ("last_status" IS NULL OR "last_status" IN ('RUNNING','OK','FAILED'))
  AND ("last_result" IS NULL OR (jsonb_typeof("last_result") = 'object' AND length("last_result"::text) <= 2000))
);
