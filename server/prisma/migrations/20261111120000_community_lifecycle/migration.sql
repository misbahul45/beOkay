-- AlterTable
ALTER TABLE "challenge_participants" ADD COLUMN     "completion_status" TEXT,
ADD COLUMN     "final_active_days" INTEGER,
ADD COLUMN     "final_score" DECIMAL(6,1);

-- AlterTable
ALTER TABLE "challenges" ADD COLUMN     "closed_at" TIMESTAMPTZ(6),
ADD COLUMN     "results_at" TIMESTAMPTZ(6),
ADD COLUMN     "template_id" UUID;

-- AlterTable
ALTER TABLE "user_settings" ADD COLUMN     "community_highlights" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "challenge_templates" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "key" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "duration_days" INTEGER NOT NULL,
    "target_days" INTEGER NOT NULL,
    "cadence_days" INTEGER NOT NULL,
    "anchor_date" DATE NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "challenge_templates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "recognitions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "key" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "achieved_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "recognitions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "challenge_templates_key_key" ON "challenge_templates"("key");

-- CreateIndex
CREATE UNIQUE INDEX "recognitions_user_id_key_key" ON "recognitions"("user_id", "key");

-- CreateIndex
CREATE UNIQUE INDEX "challenges_community_id_template_id_starts_on_key" ON "challenges"("community_id", "template_id", "starts_on");

-- AddForeignKey
ALTER TABLE "challenges" ADD CONSTRAINT "challenges_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "challenge_templates"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recognitions" ADD CONSTRAINT "recognitions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "challenges" DROP CONSTRAINT "challenges_valid";
ALTER TABLE "challenges" ADD CONSTRAINT "challenges_valid" CHECK (
  "kind" IN ('ACTIVE_DAYS')
  AND "status" IN ('SCHEDULED','OPEN','CLOSED')
  AND "ends_on" > "starts_on"
  AND "target_days" BETWEEN 1 AND 90
  AND "target_days" <= ("ends_on" - "starts_on" + 1)
  AND ("status" <> 'CLOSED' OR "closed_at" IS NOT NULL OR "template_id" IS NULL)
  AND ("results_at" IS NULL OR "status" = 'CLOSED')
);

ALTER TABLE "challenge_templates" ADD CONSTRAINT "challenge_templates_valid" CHECK (
  "kind" IN ('ACTIVE_DAYS')
  AND "duration_days" BETWEEN 2 AND 90
  AND "target_days" BETWEEN 1 AND "duration_days"
  AND "cadence_days" BETWEEN "duration_days" AND 365
  AND length("key") BETWEEN 1 AND 60
  AND length("title") BETWEEN 1 AND 80
  AND length("description") BETWEEN 1 AND 400
);

ALTER TABLE "challenge_participants" ADD CONSTRAINT "challenge_participants_result_valid" CHECK (
  ("completion_status" IS NULL OR "completion_status" IN ('COMPLETED','PARTICIPATED','LEFT'))
  AND ("final_active_days" IS NULL OR "final_active_days" >= 0)
  AND ("final_score" IS NULL OR "final_score" BETWEEN 0 AND 100)
);

ALTER TABLE "recognitions" ADD CONSTRAINT "recognitions_valid" CHECK (
  "category" IN ('CHALLENGE','REFLECTION','PLAN','LOGGING')
  AND length("key") BETWEEN 1 AND 60
  AND length("title") BETWEEN 1 AND 80
  AND length("detail") BETWEEN 1 AND 200
);

INSERT INTO "challenge_templates" ("key","title","description","kind","duration_days","target_days","cadence_days","anchor_date") VALUES
  ('weekly-active-3', '3 hari aktif minggu ini', 'Hari aktif = satu sesi aktivitas tercatat (min. 10 menit) atau check-in kebiasaan. Satu hari dihitung sekali; hari istirahat tidak mengurangi skor.', 'ACTIVE_DAYS', 7, 3, 7, DATE '2026-11-02'),
  ('four-week-active-12', '12 hari aktif dalam 4 minggu', 'Hari aktif = satu sesi aktivitas tercatat (min. 10 menit) atau check-in kebiasaan. Langkah kecil yang konsisten lebih penting daripada intensitas.', 'ACTIVE_DAYS', 28, 12, 28, DATE '2026-11-02');
