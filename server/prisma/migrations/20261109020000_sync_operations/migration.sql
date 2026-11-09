-- Sync receipts: satu baris per (user, operation_id). Dipakai agar retry dari klien offline idempoten.
CREATE TABLE "sync_operations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "operation_id" UUID NOT NULL,
    "payload_hash" TEXT NOT NULL,
    "domain" TEXT NOT NULL,
    "record_id" UUID NOT NULL,
    "operation_type" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "result" JSONB,
    "error_code" TEXT,
    "completed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "sync_operations_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "sync_operations_valid" CHECK (
      "domain" IN ('meal','glucose','activity','medication_intake','goal_checkin')
      AND "operation_type" IN ('create','update')
      AND "status" IN ('SYNCED','CONFLICT','NEEDS_REVIEW','SYNC_FAILED')
    )
);
CREATE UNIQUE INDEX "sync_operations_user_id_operation_id_key" ON "sync_operations"("user_id", "operation_id");
CREATE INDEX "sync_operations_user_id_completed_at_idx" ON "sync_operations"("user_id", "completed_at" DESC);
ALTER TABLE "sync_operations" ADD CONSTRAINT "sync_operations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
