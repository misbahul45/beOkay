-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "ref_id" TEXT,
    "dedupe_key" TEXT NOT NULL,
    "pushed_at" TIMESTAMPTZ(6),
    "read_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_preferences" (
    "user_id" UUID NOT NULL,
    "push_enabled" BOOLEAN NOT NULL DEFAULT true,
    "muted_kinds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("user_id")
);

-- CreateIndex
CREATE INDEX "notifications_user_id_created_at_idx" ON "notifications"("user_id", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "notifications_user_id_dedupe_key_key" ON "notifications"("user_id", "dedupe_key");

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_preferences" ADD CONSTRAINT "notification_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "notifications" ADD CONSTRAINT "notifications_valid" CHECK (
  "kind" IN ('REMINDER','COACHING','REFLECTION','CHALLENGE','RECOGNITION')
  AND length("title") BETWEEN 1 AND 80
  AND length("body") BETWEEN 1 AND 240
  AND "action" IN ('OPEN_HOME','OPEN_LOG','OPEN_COACHING','OPEN_REFLECTION','OPEN_CHALLENGE','OPEN_COMMUNITY','OPEN_RECOGNITIONS','OPEN_REMINDERS','OPEN_GOALS','OPEN_MEDICATIONS')
  AND length("dedupe_key") BETWEEN 1 AND 200
);

ALTER TABLE "notification_preferences" ADD CONSTRAINT "notification_preferences_valid" CHECK (
  "muted_kinds" <@ ARRAY['REMINDER','COACHING','REFLECTION','CHALLENGE','RECOGNITION']::TEXT[]
);
