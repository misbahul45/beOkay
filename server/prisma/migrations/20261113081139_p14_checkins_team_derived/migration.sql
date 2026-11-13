-- AlterTable
ALTER TABLE "challenge_templates" ADD COLUMN     "team_target_days" INTEGER;

-- AlterTable
ALTER TABLE "challenges" ADD COLUMN     "team_target_days" INTEGER;

-- CreateTable
CREATE TABLE "daily_checkins" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "local_date" DATE NOT NULL,
    "energy" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "daily_checkins_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "daily_checkins_user_id_local_date_key" ON "daily_checkins"("user_id", "local_date");

-- AddForeignKey
ALTER TABLE "daily_checkins" ADD CONSTRAINT "daily_checkins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "daily_checkins" ADD CONSTRAINT "daily_checkins_energy_check" CHECK ("energy" IN ('LOW','OK','HIGH') AND "version" >= 1);

ALTER TABLE "challenges" DROP CONSTRAINT "challenges_valid";
ALTER TABLE "challenges" ADD CONSTRAINT "challenges_valid" CHECK (
  "kind" IN ('ACTIVE_DAYS','TEAM_ACTIVE_DAYS')
  AND "status" IN ('SCHEDULED','OPEN','CLOSED')
  AND "ends_on" > "starts_on"
  AND "target_days" BETWEEN 1 AND 90
  AND "target_days" <= ("ends_on" - "starts_on" + 1)
  AND ("status" <> 'CLOSED' OR "closed_at" IS NOT NULL OR "template_id" IS NULL)
  AND ("results_at" IS NULL OR "status" = 'CLOSED')
  AND (("kind" = 'TEAM_ACTIVE_DAYS') = ("team_target_days" IS NOT NULL))
  AND ("team_target_days" IS NULL OR "team_target_days" BETWEEN 1 AND 5000)
);

ALTER TABLE "memory_items" DROP CONSTRAINT "memory_items_valid";
ALTER TABLE "memory_items" ADD CONSTRAINT "memory_items_valid"
  CHECK (
    "category" IN ('PREFERENCE','EPISODIC')
    AND "kind" IN ('ACTIVITY_TIME','SCHEDULE','ACTIVITY_LIKE','ACTIVITY_DISLIKE','AVAILABLE_MINUTES','FOOD_CONTEXT','BARRIER','HEALTH_EVENT')
    AND "status" IN ('PROPOSED','ACTIVE','DISMISSED')
    AND "source_type" IN ('CONVERSATION','USER','LANGUAGE_MODEL','DERIVED','CHALLENGE')
    AND "confidence" IN ('STATED','INFERRED')
    AND "sensitivity" IN ('LOW','MEDIUM')
    AND "retention" IN ('UNTIL_DELETED','EXPIRES')
    AND length("content") BETWEEN 1 AND 160
    AND length("key") BETWEEN 1 AND 120
    AND "version" >= 1
    AND ("status" <> 'ACTIVE' OR "confirmed_at" IS NOT NULL)
    AND (("retention" = 'EXPIRES') = ("expires_at" IS NOT NULL))
  );

ALTER TABLE "challenge_templates" DROP CONSTRAINT "challenge_templates_valid";
ALTER TABLE "challenge_templates" ADD CONSTRAINT "challenge_templates_valid" CHECK (
  "kind" IN ('ACTIVE_DAYS','TEAM_ACTIVE_DAYS')
  AND "duration_days" BETWEEN 2 AND 90
  AND "target_days" BETWEEN 1 AND "duration_days"
  AND "cadence_days" BETWEEN "duration_days" AND 365
  AND length("key") BETWEEN 1 AND 60
  AND length("title") BETWEEN 1 AND 80
  AND length("description") BETWEEN 1 AND 400
  AND (("kind" = 'TEAM_ACTIVE_DAYS') = ("team_target_days" IS NOT NULL))
);

INSERT INTO "challenge_templates" ("key","title","description","kind","duration_days","target_days","team_target_days","cadence_days","anchor_date","enabled") VALUES
  ('misi-tim-7-hari','Misi tim: 7 hari bergerak bersama','Setiap hari aktif anggota menambah progres tim. Yang tampil hanya jumlah tim, tanpa nama dan tanpa nilai kesehatan.','TEAM_ACTIVE_DAYS',7,3,20,7,'2026-11-16',true)
ON CONFLICT ("key") DO NOTHING;
