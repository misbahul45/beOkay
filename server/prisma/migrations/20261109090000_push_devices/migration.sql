-- Perangkat untuk notifikasi push (FCM) dan buku besar pengiriman pengingat.
-- Pengiriman dijaga unik per (pengingat, perangkat, waktu jadwal) sehingga pemicu ganda/instans ganda tidak mengirim dua kali.
CREATE TABLE "push_devices" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "token" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "app_version" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "last_error" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "push_devices_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "push_devices_valid" CHECK ("platform" IN ('android','ios') AND length("token") BETWEEN 20 AND 4096 AND ("app_version" IS NULL OR length("app_version") <= 40) AND ("last_error" IS NULL OR length("last_error") <= 200))
);
CREATE UNIQUE INDEX "push_devices_token_key" ON "push_devices"("token");
CREATE INDEX "push_devices_user_id_active_idx" ON "push_devices"("user_id", "active");
ALTER TABLE "push_devices" ADD CONSTRAINT "push_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "push_deliveries" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "reminder_id" UUID NOT NULL,
    "device_id" UUID NOT NULL,
    "scheduled_at" TIMESTAMPTZ(6) NOT NULL,
    "status" TEXT NOT NULL,
    "provider_message_id" TEXT,
    "error_code" TEXT,
    "attempted_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "push_deliveries_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "push_deliveries_valid" CHECK ("status" IN ('pending','sent','failed','invalid_token') AND ("error_code" IS NULL OR length("error_code") <= 100))
);
CREATE UNIQUE INDEX "push_deliveries_reminder_id_device_id_scheduled_at_key" ON "push_deliveries"("reminder_id", "device_id", "scheduled_at");
CREATE INDEX "push_deliveries_user_id_attempted_at_idx" ON "push_deliveries"("user_id", "attempted_at");
ALTER TABLE "push_deliveries" ADD CONSTRAINT "push_deliveries_reminder_id_fkey" FOREIGN KEY ("reminder_id") REFERENCES "reminders"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "push_deliveries" ADD CONSTRAINT "push_deliveries_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "push_devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;
