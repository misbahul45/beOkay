-- Komunitas lokal berbasis wilayah (tingkat PROVINSI saja), tantangan kebiasaan, buku besar skor append-only.
-- Privasi: tabel komunitas TIDAK punya FK ke profil/ukuran kesehatan; identitas publik = alias; tanpa koordinat/alamat.
CREATE TABLE "regions" ("code" TEXT NOT NULL, "name" TEXT NOT NULL, "level" TEXT NOT NULL DEFAULT 'PROVINCE', CONSTRAINT "regions_pkey" PRIMARY KEY ("code"), CONSTRAINT "regions_valid" CHECK ("level" = 'PROVINCE' AND "code" ~ '^[0-9]{2}$'));
INSERT INTO "regions" ("code","name") VALUES
('11','Aceh'),
('12','Sumatera Utara'),
('13','Sumatera Barat'),
('14','Riau'),
('15','Jambi'),
('16','Sumatera Selatan'),
('17','Bengkulu'),
('18','Lampung'),
('19','Kepulauan Bangka Belitung'),
('21','Kepulauan Riau'),
('31','DKI Jakarta'),
('32','Jawa Barat'),
('33','Jawa Tengah'),
('34','DI Yogyakarta'),
('35','Jawa Timur'),
('36','Banten'),
('51','Bali'),
('52','Nusa Tenggara Barat'),
('53','Nusa Tenggara Timur'),
('61','Kalimantan Barat'),
('62','Kalimantan Tengah'),
('63','Kalimantan Selatan'),
('64','Kalimantan Timur'),
('65','Kalimantan Utara'),
('71','Sulawesi Utara'),
('72','Sulawesi Tengah'),
('73','Sulawesi Selatan'),
('74','Sulawesi Tenggara'),
('75','Gorontalo'),
('76','Sulawesi Barat'),
('81','Maluku'),
('82','Maluku Utara'),
('91','Papua'),
('92','Papua Barat'),
('93','Papua Selatan'),
('94','Papua Tengah'),
('95','Papua Pegunungan'),
('96','Papua Barat Daya');

CREATE TABLE "communities" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "region_code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "communities_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "communities_valid" CHECK (length(btrim("name")) BETWEEN 3 AND 100)
);
CREATE UNIQUE INDEX "communities_region_code_name_key" ON "communities"("region_code", "name");
CREATE INDEX "communities_region_code_idx" ON "communities"("region_code");
ALTER TABLE "communities" ADD CONSTRAINT "communities_region_code_fkey" FOREIGN KEY ("region_code") REFERENCES "regions"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
INSERT INTO "communities" ("region_code","name","description")
  SELECT "code", 'Hidup Seimbang ' || "name", 'Komunitas kebiasaan sehat untuk wilayah ' || "name" || '. Bergabung bersifat sukarela; yang terlihat hanya aliasmu.' FROM "regions";

CREATE TABLE "community_memberships" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "community_id" UUID NOT NULL,
    "alias" TEXT NOT NULL,
    "alias_key" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "joined_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "left_at" TIMESTAMPTZ(6),
    CONSTRAINT "community_memberships_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "community_memberships_valid" CHECK ("status" IN ('ACTIVE','LEFT') AND "alias" ~ '^[A-Za-z0-9][A-Za-z0-9 _.-]{2,19}$')
);
CREATE UNIQUE INDEX "community_memberships_user_id_community_id_key" ON "community_memberships"("user_id", "community_id");
-- Alias unik per komunitas selama aktif (mencegah peniruan), tanpa membedakan huruf besar/kecil.
CREATE UNIQUE INDEX "community_memberships_active_alias" ON "community_memberships"("community_id", "alias_key") WHERE "status" = 'ACTIVE';
CREATE INDEX "community_memberships_community_id_status_idx" ON "community_memberships"("community_id", "status");
ALTER TABLE "community_memberships" ADD CONSTRAINT "community_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "community_memberships" ADD CONSTRAINT "community_memberships_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "communities"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "challenges" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "community_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "starts_on" DATE NOT NULL,
    "ends_on" DATE NOT NULL,
    "target_days" INTEGER NOT NULL,
    "scoring_version" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "challenges_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "challenges_valid" CHECK ("kind" IN ('ACTIVE_DAYS') AND "status" IN ('OPEN','CLOSED') AND "ends_on" > "starts_on" AND "target_days" BETWEEN 1 AND 90 AND "target_days" <= ("ends_on" - "starts_on" + 1))
);
CREATE INDEX "challenges_community_id_status_idx" ON "challenges"("community_id", "status");
ALTER TABLE "challenges" ADD CONSTRAINT "challenges_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "communities"("id") ON DELETE CASCADE ON UPDATE CASCADE;
-- Tantangan bawaan: 4 pekan, target 20 hari aktif (5 hari/pekan). Manual maupun perangkat dihitung; tidak perlu jam tangan.
INSERT INTO "challenges" ("community_id","title","description","kind","starts_on","ends_on","target_days","scoring_version","status")
  SELECT "id", 'Aktif 5 hari seminggu', 'Hari aktif = ada satu sesi aktivitas tercatat (min. 10 menit) atau check-in kebiasaan sukarela. Satu hari dihitung sekali; hari istirahat tidak mengurangi skor.', 'ACTIVE_DAYS', CURRENT_DATE, CURRENT_DATE + 27, 20, 'score-v1', 'OPEN' FROM "communities";

CREATE TABLE "challenge_participants" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "challenge_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "leaderboard_visible" BOOLEAN NOT NULL DEFAULT false,
    "joined_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "left_at" TIMESTAMPTZ(6),
    CONSTRAINT "challenge_participants_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "challenge_participants_challenge_id_user_id_key" ON "challenge_participants"("challenge_id", "user_id");
ALTER TABLE "challenge_participants" ADD CONSTRAINT "challenge_participants_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "challenges"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "challenge_participants" ADD CONSTRAINT "challenge_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "challenge_checkins" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "challenge_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "local_date" DATE NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "challenge_checkins_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "challenge_checkins_challenge_id_user_id_local_date_key" ON "challenge_checkins"("challenge_id", "user_id", "local_date");
ALTER TABLE "challenge_checkins" ADD CONSTRAINT "challenge_checkins_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "challenges"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "challenge_checkins" ADD CONSTRAINT "challenge_checkins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "score_events" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "challenge_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "event_type" TEXT NOT NULL,
    "source_key" TEXT NOT NULL,
    "local_date" DATE,
    "points" DECIMAL(10,4) NOT NULL,
    "scoring_version" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "reversal_of" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "score_events_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "score_events_valid" CHECK ("event_type" IN ('ACTIVITY_DAY','CHECKIN_DAY','PARTICIPATION') AND (("reversal_of" IS NULL AND "points" >= 0) OR ("reversal_of" IS NOT NULL AND "points" <= 0)))
);
CREATE UNIQUE INDEX "score_events_reversal_of_key" ON "score_events"("reversal_of");
-- Satu poin per sumber per peserta (hanya baris asli); pembalikan memakai reversal_of.
CREATE UNIQUE INDEX "score_events_original_unique" ON "score_events"("challenge_id", "user_id", "event_type", "source_key") WHERE "reversal_of" IS NULL;
CREATE INDEX "score_events_challenge_id_user_id_idx" ON "score_events"("challenge_id", "user_id");
ALTER TABLE "score_events" ADD CONSTRAINT "score_events_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "challenges"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "score_events" ADD CONSTRAINT "score_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "score_events" ADD CONSTRAINT "score_events_reversal_of_fkey" FOREIGN KEY ("reversal_of") REFERENCES "score_events"("id") ON DELETE CASCADE ON UPDATE CASCADE;
-- Buku besar append-only: baris asli tidak boleh diubah atau dihapus langsung (hanya cascade dari akun/tantangan).
CREATE FUNCTION score_events_immutable() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'score_events bersifat append-only'; END IF;
  RETURN OLD; END $$;
CREATE TRIGGER score_events_no_update BEFORE UPDATE ON "score_events" FOR EACH ROW EXECUTE FUNCTION score_events_immutable();

ALTER TABLE "consent_records" DROP CONSTRAINT "consent_records_purpose_valid";
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_purpose_valid"
  CHECK ("purpose" IN ('health_data_processing','descriptive_summaries','product_analytics','personalized_ai','community_membership','challenge_participation','leaderboard_visibility'));
