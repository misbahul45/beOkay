-- Ukuran rumah tangga per makanan (mis. "1 sendok makan" = 15 g). Tidak ada tabel konversi umum:
-- gram per ukuran hanya ada bila pengguna menimbang/memperkirakannya untuk makanan itu.
CREATE TABLE "food_portion_measures" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "food_id" UUID NOT NULL,
    "label" TEXT NOT NULL,
    "grams" DECIMAL(12,4) NOT NULL,
    "basis" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "food_portion_measures_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "food_portion_measures_valid" CHECK ("grams" > 0 AND "grams" <= 1000000 AND "basis" IN ('weighed','user_estimate') AND length(btrim("label")) BETWEEN 1 AND 60)
);
CREATE UNIQUE INDEX "food_portion_measures_user_id_food_id_label_key" ON "food_portion_measures"("user_id", "food_id", "label");
CREATE INDEX "food_portion_measures_food_id_idx" ON "food_portion_measures"("food_id");
ALTER TABLE "food_portion_measures" ADD CONSTRAINT "food_portion_measures_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "food_portion_measures" ADD CONSTRAINT "food_portion_measures_food_id_fkey" FOREIGN KEY ("food_id") REFERENCES "food_catalog"("id") ON DELETE CASCADE ON UPDATE CASCADE;
