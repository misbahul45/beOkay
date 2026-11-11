-- CreateTable
CREATE TABLE "conversation_threads" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "title" TEXT,
    "last_run_id" UUID,
    "message_count" INTEGER NOT NULL DEFAULT 0,
    "last_message_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "conversation_threads_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "conversation_messages" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "thread_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "seq" INTEGER NOT NULL,
    "role" TEXT NOT NULL,
    "client_message_id" UUID,
    "reply_to_id" UUID,
    "text" TEXT,
    "parts" JSONB NOT NULL DEFAULT '[]',
    "route" TEXT,
    "router_version" TEXT,
    "run_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "conversation_messages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "conversation_threads_user_id_last_message_at_idx" ON "conversation_threads"("user_id", "last_message_at" DESC);

-- CreateIndex
CREATE INDEX "conversation_threads_last_run_id_idx" ON "conversation_threads"("last_run_id");

-- CreateIndex
CREATE UNIQUE INDEX "conversation_messages_reply_to_id_key" ON "conversation_messages"("reply_to_id");

-- CreateIndex
CREATE INDEX "conversation_messages_run_id_idx" ON "conversation_messages"("run_id");

-- CreateIndex
CREATE UNIQUE INDEX "conversation_messages_user_id_client_message_id_key" ON "conversation_messages"("user_id", "client_message_id");

-- CreateIndex
CREATE UNIQUE INDEX "conversation_messages_thread_id_seq_key" ON "conversation_messages"("thread_id", "seq");

-- AddForeignKey
ALTER TABLE "conversation_threads" ADD CONSTRAINT "conversation_threads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversation_threads" ADD CONSTRAINT "conversation_threads_last_run_id_fkey" FOREIGN KEY ("last_run_id") REFERENCES "agent_runs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversation_messages" ADD CONSTRAINT "conversation_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "conversation_threads"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversation_messages" ADD CONSTRAINT "conversation_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversation_messages" ADD CONSTRAINT "conversation_messages_reply_to_id_fkey" FOREIGN KEY ("reply_to_id") REFERENCES "conversation_messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversation_messages" ADD CONSTRAINT "conversation_messages_run_id_fkey" FOREIGN KEY ("run_id") REFERENCES "agent_runs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "conversation_threads" ADD CONSTRAINT "conversation_threads_valid"
  CHECK ("message_count" BETWEEN 0 AND 400 AND ("title" IS NULL OR length("title") BETWEEN 1 AND 80));

ALTER TABLE "conversation_messages" ADD CONSTRAINT "conversation_messages_valid"
  CHECK (
    "seq" >= 1
    AND jsonb_typeof("parts") = 'array'
    AND (
      ("role" = 'USER' AND "client_message_id" IS NOT NULL AND "reply_to_id" IS NULL AND "text" IS NOT NULL AND length("text") BETWEEN 1 AND 1000)
      OR ("role" = 'ASSISTANT' AND "client_message_id" IS NULL AND "reply_to_id" IS NOT NULL AND "text" IS NULL AND "route" IS NOT NULL AND "router_version" IS NOT NULL)
    )
  );
