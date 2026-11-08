-- CreateTable
CREATE TABLE "food_catalog" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "name" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "source_version" TEXT,
    "status" TEXT NOT NULL,
    "calories" DECIMAL(12,4),
    "carbohydrates" DECIMAL(12,4),
    "protein" DECIMAL(12,4),
    "fat" DECIMAL(12,4),
    "fiber" DECIMAL(12,4),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "food_catalog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "meal_logs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "category" TEXT NOT NULL,
    "consumed_at" TIMESTAMPTZ(6) NOT NULL,
    "notes" TEXT,
    "capture_method" TEXT NOT NULL DEFAULT 'manual',
    "create_hash" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "meal_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "meal_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "meal_id" UUID NOT NULL,
    "food_id" UUID,
    "name" TEXT NOT NULL,
    "quantity" DECIMAL(12,4) NOT NULL,
    "unit" TEXT NOT NULL,
    "grams" DECIMAL(12,4),
    "grams_basis" TEXT,
    "source" TEXT NOT NULL,
    "source_version" TEXT,
    "status" TEXT NOT NULL,
    "calories" DECIMAL(12,4),
    "carbohydrates" DECIMAL(12,4),
    "protein" DECIMAL(12,4),
    "fat" DECIMAL(12,4),
    "fiber" DECIMAL(12,4),

    CONSTRAINT "meal_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "record_revisions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "meal_id" UUID NOT NULL,
    "version" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "snapshot" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "record_revisions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "food_catalog_user_id_name_idx" ON "food_catalog"("user_id", "name");

-- CreateIndex
CREATE INDEX "meal_logs_user_id_consumed_at_id_idx" ON "meal_logs"("user_id", "consumed_at" DESC, "id" DESC);

-- CreateIndex
CREATE INDEX "meal_items_meal_id_idx" ON "meal_items"("meal_id");

-- CreateIndex
CREATE INDEX "meal_items_food_id_idx" ON "meal_items"("food_id");

-- CreateIndex
CREATE INDEX "record_revisions_user_id_created_at_idx" ON "record_revisions"("user_id", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "record_revisions_meal_id_version_key" ON "record_revisions"("meal_id", "version");

-- AddForeignKey
ALTER TABLE "food_catalog" ADD CONSTRAINT "food_catalog_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "meal_logs" ADD CONSTRAINT "meal_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "meal_items" ADD CONSTRAINT "meal_items_meal_id_fkey" FOREIGN KEY ("meal_id") REFERENCES "meal_logs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "meal_items" ADD CONSTRAINT "meal_items_food_id_fkey" FOREIGN KEY ("food_id") REFERENCES "food_catalog"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "record_revisions" ADD CONSTRAINT "record_revisions_meal_id_fkey" FOREIGN KEY ("meal_id") REFERENCES "meal_logs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE food_catalog ADD CONSTRAINT food_catalog_valid CHECK (
  length(trim(name)) BETWEEN 1 AND 120 AND length(trim(source)) BETWEEN 1 AND 160
  AND status IN ('user_reported','estimated')
  AND (calories IS NULL OR calories BETWEEN 0 AND 10000)
  AND (carbohydrates IS NULL OR carbohydrates BETWEEN 0 AND 10000)
  AND (protein IS NULL OR protein BETWEEN 0 AND 10000)
  AND (fat IS NULL OR fat BETWEEN 0 AND 10000)
  AND (fiber IS NULL OR fiber BETWEEN 0 AND 10000)
);
ALTER TABLE meal_logs ADD CONSTRAINT meal_logs_valid CHECK (
  category IN ('breakfast','lunch','dinner','snack') AND version > 0
  AND capture_method = 'manual' AND length(create_hash) = 64
  AND consumed_at >= '1900-01-01'::timestamptz AND length(notes) <= 2000
);
ALTER TABLE meal_items ADD CONSTRAINT meal_items_valid CHECK (
  length(trim(name)) BETWEEN 1 AND 120 AND quantity > 0 AND quantity <= 10000
  AND unit IN ('g','portion','piece','ml') AND status IN ('unknown','user_reported','estimated')
  AND ((grams IS NULL AND grams_basis IS NULL) OR (grams IS NOT NULL AND grams_basis IS NOT NULL AND grams > 0 AND grams <= 1000000 AND grams_basis IN ('weighed','user_estimate')))
  AND (unit <> 'g' OR (grams IS NOT NULL AND grams_basis IS NOT NULL AND grams = quantity AND grams_basis = 'weighed'))
  AND (calories IS NULL OR calories BETWEEN 0 AND 10000)
  AND (carbohydrates IS NULL OR carbohydrates BETWEEN 0 AND 10000)
  AND (protein IS NULL OR protein BETWEEN 0 AND 10000)
  AND (fat IS NULL OR fat BETWEEN 0 AND 10000)
  AND (fiber IS NULL OR fiber BETWEEN 0 AND 10000)
);
ALTER TABLE record_revisions ADD CONSTRAINT record_revisions_valid CHECK (version > 0 AND length(trim(reason)) BETWEEN 1 AND 300 AND jsonb_typeof(snapshot) = 'object');
