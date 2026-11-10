-- Pengingat lokal. Server hanya menyimpan aturan (jam lokal + hari) dan menghitung kejadian berikutnya;
-- penjadwalan notifikasi dilakukan di perangkat. Zona waktu mengikuti pengaturan pengguna (aman untuk DST).
CREATE TABLE "reminders" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "local_time" TEXT NOT NULL,
    "days_of_week" SMALLINT[] NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "version" INTEGER NOT NULL DEFAULT 1,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "reminders_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "reminders_valid" CHECK (
        "kind" IN ('medication','glucose','meal','activity','goal','custom')
        AND length(btrim("title")) BETWEEN 1 AND 80
        AND "local_time" ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        AND cardinality("days_of_week") BETWEEN 1 AND 7
        AND "days_of_week" <@ ARRAY[1,2,3,4,5,6,7]::smallint[]
        AND "version" >= 1
    )
);
CREATE INDEX "reminders_user_id_archived_at_idx" ON "reminders"("user_id", "archived_at");
ALTER TABLE "reminders" ADD CONSTRAINT "reminders_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
