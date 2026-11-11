-- AlterTable
ALTER TABLE "conversation_messages" ADD COLUMN     "basis" JSONB;

-- AlterTable
ALTER TABLE "conversation_threads" ADD COLUMN     "context" JSONB NOT NULL DEFAULT '{}';

-- AlterTable
ALTER TABLE "user_settings" ADD COLUMN     "memory_enabled" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "meal_drafts" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "thread_id" UUID,
    "source" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PROPOSED',
    "category" TEXT NOT NULL,
    "consumed_at" TIMESTAMPTZ(6) NOT NULL,
    "input_text" TEXT,
    "items" JSONB NOT NULL DEFAULT '[]',
    "meal_id" UUID,
    "version" INTEGER NOT NULL DEFAULT 1,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "resolved_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "meal_drafts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "memory_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "category" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PROPOSED',
    "source_type" TEXT NOT NULL,
    "source_id" UUID,
    "confidence" TEXT NOT NULL DEFAULT 'STATED',
    "sensitivity" TEXT NOT NULL DEFAULT 'LOW',
    "retention" TEXT NOT NULL DEFAULT 'UNTIL_DELETED',
    "version" INTEGER NOT NULL DEFAULT 1,
    "confirmed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "memory_items_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "meal_drafts_meal_id_key" ON "meal_drafts"("meal_id");

-- CreateIndex
CREATE INDEX "meal_drafts_user_id_created_at_idx" ON "meal_drafts"("user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "meal_drafts_thread_id_idx" ON "meal_drafts"("thread_id");

-- CreateIndex
CREATE INDEX "memory_items_user_id_status_idx" ON "memory_items"("user_id", "status");

-- AddForeignKey
ALTER TABLE "meal_drafts" ADD CONSTRAINT "meal_drafts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "meal_drafts" ADD CONSTRAINT "meal_drafts_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "conversation_threads"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "meal_drafts" ADD CONSTRAINT "meal_drafts_meal_id_fkey" FOREIGN KEY ("meal_id") REFERENCES "meal_logs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memory_items" ADD CONSTRAINT "memory_items_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "meal_drafts" ADD CONSTRAINT "meal_drafts_valid"
  CHECK (
    "source" IN ('TEXT','PHOTO')
    AND "status" IN ('PROPOSED','SAVED','DISCARDED')
    AND "category" IN ('breakfast','lunch','dinner','snack')
    AND jsonb_typeof("items") = 'array'
    AND "version" >= 1
    AND ("input_text" IS NULL OR length("input_text") BETWEEN 1 AND 1000)
    AND (("status" = 'PROPOSED') = ("resolved_at" IS NULL))
  );

ALTER TABLE "memory_items" ADD CONSTRAINT "memory_items_valid"
  CHECK (
    "category" IN ('PREFERENCE','EPISODIC')
    AND "kind" IN ('ACTIVITY_TIME','SCHEDULE','ACTIVITY_LIKE','ACTIVITY_DISLIKE','AVAILABLE_MINUTES')
    AND "status" IN ('PROPOSED','ACTIVE','DISMISSED')
    AND "source_type" IN ('CONVERSATION','USER')
    AND "confidence" IN ('STATED')
    AND "sensitivity" IN ('LOW')
    AND "retention" IN ('UNTIL_DELETED')
    AND length("content") BETWEEN 1 AND 160
    AND length("key") BETWEEN 1 AND 120
    AND "version" >= 1
    AND ("status" <> 'ACTIVE' OR "confirmed_at" IS NOT NULL)
  );

CREATE UNIQUE INDEX "memory_items_active_key" ON "memory_items"("user_id", "key") WHERE "status" = 'ACTIVE';
CREATE UNIQUE INDEX "memory_items_proposed_key" ON "memory_items"("user_id", "key") WHERE "status" = 'PROPOSED';

ALTER TABLE "conversation_threads" ADD CONSTRAINT "conversation_threads_context_object" CHECK (jsonb_typeof("context") = 'object');
ALTER TABLE "conversation_messages" ADD CONSTRAINT "conversation_messages_basis_object" CHECK ("basis" IS NULL OR jsonb_typeof("basis") = 'object');
