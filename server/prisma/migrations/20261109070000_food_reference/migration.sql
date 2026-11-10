-- Referensi komposisi pangan (Tabel Komposisi Pangan Indonesia) untuk pencarian lokal-dahulu dan RAG.
-- Hanya baris `verified_auto` (lolos Atwater + jumlah proksimat) yang boleh dipakai kalkulator/agen;
-- `needs_review` disimpan untuk ditinjau tetapi dikecualikan dari pencarian. `verified_auto` BUKAN verifikasi manusia.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE "food_reference" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "name_normalized" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "source_version" TEXT NOT NULL,
    "source_ref" TEXT,
    "page" INTEGER,
    "chapter" TEXT,
    "status" TEXT NOT NULL,
    "flags" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "water" DECIMAL(12,4),
    "calories" DECIMAL(12,4),
    "protein" DECIMAL(12,4),
    "fat" DECIMAL(12,4),
    "carbohydrates" DECIMAL(12,4),
    "fiber" DECIMAL(12,4),
    "ash" DECIMAL(12,4),
    "embedding" vector(1024),
    "embedding_model" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "food_reference_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "food_reference_valid" CHECK (
        "status" IN ('verified_auto','needs_review')
        AND length(btrim("name")) BETWEEN 1 AND 200
        AND ("water" IS NULL OR "water" BETWEEN 0 AND 100)
        AND ("calories" IS NULL OR "calories" BETWEEN 0 AND 950)
        AND ("protein" IS NULL OR "protein" BETWEEN 0 AND 100)
        AND ("fat" IS NULL OR "fat" BETWEEN 0 AND 100)
        AND ("carbohydrates" IS NULL OR "carbohydrates" BETWEEN 0 AND 100)
        AND ("fiber" IS NULL OR "fiber" BETWEEN 0 AND 100)
        AND ("ash" IS NULL OR "ash" BETWEEN 0 AND 100)
        -- baris yang dipakai wajib punya empat makro inti
        AND ("status" <> 'verified_auto' OR ("calories" IS NOT NULL AND "protein" IS NOT NULL AND "fat" IS NOT NULL AND "carbohydrates" IS NOT NULL))
    )
);
CREATE UNIQUE INDEX "food_reference_code_key" ON "food_reference"("code");
CREATE INDEX "food_reference_status_idx" ON "food_reference"("status");
CREATE INDEX "food_reference_name_trgm_idx" ON "food_reference" USING GIN ("name_normalized" gin_trgm_ops);
CREATE INDEX "food_reference_embedding_idx" ON "food_reference" USING hnsw ("embedding" vector_cosine_ops);
