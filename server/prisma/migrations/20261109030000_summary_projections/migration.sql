-- Proyeksi ringkasan: turunan saja, bukan sumber data. Dibuat ulang dari tabel sumber kapan saja.
CREATE TABLE "summary_projections" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "period_start" DATE NOT NULL,
    "computation_version" TEXT NOT NULL,
    "coverage_status" TEXT NOT NULL,
    "freshness_status" TEXT NOT NULL DEFAULT 'CURRENT',
    "analytics_state" TEXT NOT NULL,
    "metrics" JSONB NOT NULL,
    "computed_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "summary_projections_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "summary_projections_valid" CHECK (
      "kind" IN ('daily','weekly')
      AND "freshness_status" IN ('CURRENT','STALE')
      AND "coverage_status" IN ('UNKNOWN','PARTIAL','COMPLETE')
      AND "analytics_state" IN ('NOT_AVAILABLE','COMPUTING','READY','INSUFFICIENT_DATA','STALE','ERROR')
    )
);
CREATE UNIQUE INDEX "summary_projections_user_id_kind_period_start_computation_v_key" ON "summary_projections"("user_id", "kind", "period_start", "computation_version");
ALTER TABLE "summary_projections" ADD CONSTRAINT "summary_projections_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
