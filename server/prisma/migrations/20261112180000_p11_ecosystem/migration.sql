-- AlterTable
ALTER TABLE "community_memberships" ADD COLUMN     "hidden_at" TIMESTAMPTZ(6);

-- AlterTable
ALTER TABLE "food_reference" ADD COLUMN     "method" TEXT,
ADD COLUMN     "serving_max_g" DECIMAL(8,2),
ADD COLUMN     "serving_min_g" DECIMAL(8,2),
ADD COLUMN     "serving_typical_g" DECIMAL(8,2);

-- CreateTable
CREATE TABLE "education_modules" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "key" TEXT NOT NULL,
    "version" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "summary" TEXT NOT NULL,
    "topics" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "read_minutes" INTEGER NOT NULL,
    "body" TEXT NOT NULL,
    "content_hash" TEXT NOT NULL,
    "review_status" TEXT NOT NULL,
    "reviewed_by" TEXT,
    "reviewed_at" TIMESTAMPTZ(6),
    "authored_on" DATE NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "education_modules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "food_recipe_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "food_id" UUID NOT NULL,
    "ingredient_id" UUID NOT NULL,
    "grams" DECIMAL(8,2) NOT NULL,
    "position" INTEGER NOT NULL,

    CONSTRAINT "food_recipe_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "companion_links" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "label" TEXT NOT NULL,
    "token_hash" TEXT NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),
    "last_viewed_at" TIMESTAMPTZ(6),
    "view_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "companion_links_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cgm_imports" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "source" TEXT NOT NULL,
    "file_name" TEXT,
    "device" TEXT,
    "unit" TEXT NOT NULL,
    "rows_total" INTEGER NOT NULL,
    "rows_accepted" INTEGER NOT NULL,
    "rows_duplicate" INTEGER NOT NULL,
    "rows_skipped" INTEGER NOT NULL,
    "period_start" TIMESTAMPTZ(6),
    "period_end" TIMESTAMPTZ(6),
    "parser_version" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cgm_imports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cgm_readings" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "import_id" UUID NOT NULL,
    "measured_at" TIMESTAMPTZ(6) NOT NULL,
    "value_mg_dl" DECIMAL(6,1) NOT NULL,
    "kind" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cgm_readings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "community_reports" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "membership_id" UUID NOT NULL,
    "community_id" UUID NOT NULL,
    "alias_key" TEXT NOT NULL,
    "alias_snapshot" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolved_at" TIMESTAMPTZ(6),
    "resolution_note" TEXT,

    CONSTRAINT "community_reports_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "education_modules_review_status_idx" ON "education_modules"("review_status");

-- CreateIndex
CREATE UNIQUE INDEX "education_modules_key_version_key" ON "education_modules"("key", "version");

-- CreateIndex
CREATE INDEX "food_recipe_items_ingredient_id_idx" ON "food_recipe_items"("ingredient_id");

-- CreateIndex
CREATE UNIQUE INDEX "food_recipe_items_food_id_position_key" ON "food_recipe_items"("food_id", "position");

-- CreateIndex
CREATE UNIQUE INDEX "companion_links_token_hash_key" ON "companion_links"("token_hash");

-- CreateIndex
CREATE INDEX "companion_links_user_id_created_at_idx" ON "companion_links"("user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "cgm_imports_user_id_created_at_idx" ON "cgm_imports"("user_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "cgm_readings_user_id_measured_at_idx" ON "cgm_readings"("user_id", "measured_at");

-- CreateIndex
CREATE INDEX "cgm_readings_import_id_idx" ON "cgm_readings"("import_id");

-- CreateIndex
CREATE UNIQUE INDEX "cgm_readings_user_id_source_kind_measured_at_key" ON "cgm_readings"("user_id", "source", "kind", "measured_at");

-- CreateIndex
CREATE INDEX "community_reports_membership_id_status_idx" ON "community_reports"("membership_id", "status");

-- CreateIndex
CREATE INDEX "community_reports_status_created_at_idx" ON "community_reports"("status", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "community_reports_user_id_membership_id_alias_key_key" ON "community_reports"("user_id", "membership_id", "alias_key");

-- AddForeignKey
ALTER TABLE "food_recipe_items" ADD CONSTRAINT "food_recipe_items_food_id_fkey" FOREIGN KEY ("food_id") REFERENCES "food_reference"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "food_recipe_items" ADD CONSTRAINT "food_recipe_items_ingredient_id_fkey" FOREIGN KEY ("ingredient_id") REFERENCES "food_reference"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "companion_links" ADD CONSTRAINT "companion_links_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cgm_imports" ADD CONSTRAINT "cgm_imports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cgm_readings" ADD CONSTRAINT "cgm_readings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cgm_readings" ADD CONSTRAINT "cgm_readings_import_id_fkey" FOREIGN KEY ("import_id") REFERENCES "cgm_imports"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "community_reports" ADD CONSTRAINT "community_reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "community_reports" ADD CONSTRAINT "community_reports_membership_id_fkey" FOREIGN KEY ("membership_id") REFERENCES "community_memberships"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "education_modules" ADD CONSTRAINT "education_modules_valid" CHECK (
  "key" ~ '^[a-z0-9][a-z0-9-]{2,59}$'
  AND "version" >= 1
  AND length(btrim("title")) BETWEEN 1 AND 120
  AND length(btrim("summary")) BETWEEN 1 AND 300
  AND "read_minutes" BETWEEN 1 AND 30
  AND length("body") BETWEEN 1 AND 20000
  AND "content_hash" ~ '^[0-9a-f]{64}$'
  AND "review_status" IN ('DRAFT','REVIEWED','RETIRED')
  AND ("review_status" <> 'REVIEWED' OR ("reviewed_by" IS NOT NULL AND "reviewed_at" IS NOT NULL))
  AND ("reviewed_by" IS NULL OR length(btrim("reviewed_by")) BETWEEN 2 AND 120)
);

ALTER TABLE "food_reference" DROP CONSTRAINT "food_reference_valid";
ALTER TABLE "food_reference" ADD CONSTRAINT "food_reference_valid" CHECK (
  "status" IN ('verified_auto','needs_review','curated')
  AND length(btrim("name")) BETWEEN 1 AND 200
  AND ("water" IS NULL OR "water" BETWEEN 0 AND 100)
  AND ("calories" IS NULL OR "calories" BETWEEN 0 AND 950)
  AND ("protein" IS NULL OR "protein" BETWEEN 0 AND 100)
  AND ("fat" IS NULL OR "fat" BETWEEN 0 AND 100)
  AND ("carbohydrates" IS NULL OR "carbohydrates" BETWEEN 0 AND 100)
  AND ("fiber" IS NULL OR "fiber" BETWEEN 0 AND 100)
  AND ("ash" IS NULL OR "ash" BETWEEN 0 AND 100)
  AND ("status" NOT IN ('verified_auto','curated') OR ("calories" IS NOT NULL AND "protein" IS NOT NULL AND "fat" IS NOT NULL AND "carbohydrates" IS NOT NULL))
  AND ("status" <> 'curated' OR ("method" IS NOT NULL AND "serving_typical_g" IS NOT NULL))
  AND ("method" IS NULL OR length("method") BETWEEN 1 AND 600)
  AND ("serving_min_g" IS NULL OR "serving_min_g" > 0)
  AND ("serving_typical_g" IS NULL OR "serving_typical_g" > 0)
  AND ("serving_max_g" IS NULL OR "serving_max_g" > 0)
  AND ("serving_min_g" IS NULL OR "serving_typical_g" IS NULL OR "serving_min_g" <= "serving_typical_g")
  AND ("serving_max_g" IS NULL OR "serving_typical_g" IS NULL OR "serving_typical_g" <= "serving_max_g")
);

ALTER TABLE "food_recipe_items" ADD CONSTRAINT "food_recipe_items_valid" CHECK (
  "grams" > 0 AND "grams" <= 5000 AND "position" >= 0 AND "food_id" <> "ingredient_id"
);

ALTER TABLE "companion_links" ADD CONSTRAINT "companion_links_valid" CHECK (
  length(btrim("label")) BETWEEN 1 AND 40
  AND "token_hash" ~ '^[0-9a-f]{64}$'
  AND "expires_at" > "created_at"
  AND "view_count" >= 0
  AND ("revoked_at" IS NULL OR "revoked_at" >= "created_at")
);

ALTER TABLE "cgm_imports" ADD CONSTRAINT "cgm_imports_valid" CHECK (
  "source" IN ('LIBREVIEW')
  AND "unit" IN ('mg/dL','mmol/L')
  AND "rows_total" >= 0 AND "rows_accepted" >= 0 AND "rows_duplicate" >= 0 AND "rows_skipped" >= 0
  AND "rows_accepted" + "rows_duplicate" + "rows_skipped" = "rows_total"
  AND ("file_name" IS NULL OR length("file_name") BETWEEN 1 AND 200)
  AND ("device" IS NULL OR length("device") BETWEEN 1 AND 120)
  AND ("period_start" IS NULL) = ("period_end" IS NULL)
  AND ("period_end" IS NULL OR "period_end" >= "period_start")
  AND length("parser_version") BETWEEN 1 AND 40
);

ALTER TABLE "cgm_readings" ADD CONSTRAINT "cgm_readings_valid" CHECK (
  "kind" IN ('HISTORIC','SCAN') AND "source" IN ('LIBREVIEW') AND "value_mg_dl" BETWEEN 20 AND 600
);

ALTER TABLE "community_reports" ADD CONSTRAINT "community_reports_valid" CHECK (
  "reason" IN ('ABUSIVE','IMPERSONATION','SPAM','OTHER')
  AND "status" IN ('OPEN','UPHELD','DISMISSED','ALIAS_CHANGED')
  AND ("status" = 'OPEN') = ("resolved_at" IS NULL)
  AND ("resolution_note" IS NULL OR length("resolution_note") BETWEEN 1 AND 300)
  AND length("alias_snapshot") BETWEEN 1 AND 40
);

ALTER TABLE "consent_records" DROP CONSTRAINT "consent_records_purpose_valid";
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_purpose_valid"
  CHECK ("purpose" IN ('health_data_processing','descriptive_summaries','product_analytics','personalized_ai','community_membership','challenge_participation','leaderboard_visibility','model_inference','ai_text_generation','ai_message_understanding','companion_sharing'));

ALTER TABLE "feature_flags" DROP CONSTRAINT "feature_flags_valid";
ALTER TABLE "feature_flags" ADD CONSTRAINT "feature_flags_valid" CHECK (
  "key" IN ('assistant','conversation','coaching','community','ml_inference','food_vision','web_discovery','analytics','push','llm_router','companion','cgm')
  AND ("note" IS NULL OR length("note") <= 300)
  AND length("updated_by") BETWEEN 1 AND 120
);

ALTER TABLE "usage_events" DROP CONSTRAINT "usage_events_valid";
ALTER TABLE "usage_events" ADD CONSTRAINT "usage_events_valid" CHECK (
  "event_type" IN ('record_created','screen_opened','suggestion_offered','suggestion_accepted','suggestion_declined','notification_opened','quick_repeat_used','context_viewed','reflection_completed','strategy_chosen','vital_recorded','lab_recorded','form_saved','education_opened','voice_input_used','guest_records_migrated')
  AND ("domain" IS NULL OR "domain" IN ('meal','glucose','activity','medication','goal','vital','lab','coaching','assistant','community','notification','home','insights','settings','education','other'))
  AND jsonb_typeof("meta") = 'object'
  AND length("meta"::text) <= 400
);

ALTER TABLE "notifications" DROP CONSTRAINT "notifications_valid";
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_valid" CHECK (
  "kind" IN ('REMINDER','COACHING','REFLECTION','CHALLENGE','RECOGNITION','LAB_REMINDER','COMMUNITY')
  AND length("title") BETWEEN 1 AND 80
  AND length("body") BETWEEN 1 AND 240
  AND "action" IN ('OPEN_HOME','OPEN_LOG','OPEN_COACHING','OPEN_REFLECTION','OPEN_CHALLENGE','OPEN_COMMUNITY','OPEN_RECOGNITIONS','OPEN_REMINDERS','OPEN_GOALS','OPEN_MEDICATIONS','OPEN_CLINICAL')
  AND length("dedupe_key") BETWEEN 1 AND 200
);
