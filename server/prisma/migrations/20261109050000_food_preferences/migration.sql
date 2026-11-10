-- Alergi, pembatasan, dan preferensi makanan milik pengguna. Alergi/pembatasan = kendala keras (strict);
-- tidak suka/preferensi = lunak (soft). Disimpan sebagai data kesehatan: akses butuh consent pemrosesan data kesehatan.
CREATE TABLE "food_preferences" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "term" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "severity" TEXT NOT NULL,
    "notes" TEXT,
    "version" INTEGER NOT NULL DEFAULT 1,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "food_preferences_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "food_preferences_valid" CHECK (
        "kind" IN ('allergy','restriction','dislike','preference')
        AND "severity" IN ('strict','soft')
        AND (("kind" IN ('allergy','restriction') AND "severity" = 'strict') OR ("kind" IN ('dislike','preference') AND "severity" = 'soft'))
        AND length(btrim("term")) BETWEEN 2 AND 40
        AND length(btrim("label")) BETWEEN 2 AND 60
        AND ("notes" IS NULL OR length("notes") <= 300)
        AND "version" >= 1
    )
);
CREATE UNIQUE INDEX "food_preferences_user_id_kind_term_key" ON "food_preferences"("user_id", "kind", "term");
CREATE INDEX "food_preferences_user_id_archived_at_idx" ON "food_preferences"("user_id", "archived_at");
ALTER TABLE "food_preferences" ADD CONSTRAINT "food_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
