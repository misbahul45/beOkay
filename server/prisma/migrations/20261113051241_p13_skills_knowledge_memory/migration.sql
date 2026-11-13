-- AlterTable
ALTER TABLE "agent_runs" ADD COLUMN     "fsm_state" TEXT,
ADD COLUMN     "iterations" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "journey" TEXT,
ADD COLUMN     "skill_id" TEXT,
ADD COLUMN     "skill_version" TEXT;

-- AlterTable
ALTER TABLE "agent_tool_calls" ADD COLUMN     "iteration" INTEGER,
ADD COLUMN     "tier" TEXT;

-- AlterTable
ALTER TABLE "memory_items" ADD COLUMN     "conflict_state" TEXT NOT NULL DEFAULT 'NONE',
ADD COLUMN     "last_verified_at" TIMESTAMPTZ(6),
ADD COLUMN     "memory_type" TEXT NOT NULL DEFAULT 'FACT',
ADD COLUMN     "pause_reason" TEXT,
ADD COLUMN     "paused_at" TIMESTAMPTZ(6),
ADD COLUMN     "privacy_scope" TEXT NOT NULL DEFAULT 'PRIVATE',
ADD COLUMN     "source_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "superseded_by" UUID,
ADD COLUMN     "valid_from" TIMESTAMPTZ(6);

-- CreateTable
CREATE TABLE "memory_revisions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "memory_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "version" INTEGER NOT NULL,
    "content" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "change" TEXT NOT NULL,
    "reason" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "memory_revisions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "knowledge_documents" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "lane" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "language" TEXT NOT NULL DEFAULT 'id',
    "source_name" TEXT NOT NULL,
    "source_url" TEXT,
    "publisher" TEXT NOT NULL,
    "published_at" DATE,
    "review_status" TEXT NOT NULL DEFAULT 'DRAFT',
    "reviewed_at" TIMESTAMPTZ(6),
    "reviewer" TEXT,
    "evidence_level" TEXT NOT NULL DEFAULT 'UNGRADED',
    "allowed_journeys" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "topics" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "expires_at" DATE,
    "version" INTEGER NOT NULL DEFAULT 1,
    "content_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "knowledge_documents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "knowledge_chunks" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "document_id" UUID NOT NULL,
    "ordinal" INTEGER NOT NULL,
    "text" TEXT NOT NULL,
    "text_normalized" TEXT NOT NULL,
    "embedding" vector(1024),
    "embedding_model" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "knowledge_chunks_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "memory_revisions_user_id_created_at_idx" ON "memory_revisions"("user_id", "created_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "memory_revisions_memory_id_version_change_key" ON "memory_revisions"("memory_id", "version", "change");

-- CreateIndex
CREATE UNIQUE INDEX "knowledge_documents_slug_key" ON "knowledge_documents"("slug");

-- CreateIndex
CREATE INDEX "knowledge_documents_lane_review_status_idx" ON "knowledge_documents"("lane", "review_status");

-- CreateIndex
CREATE UNIQUE INDEX "knowledge_chunks_document_id_ordinal_key" ON "knowledge_chunks"("document_id", "ordinal");

-- AddForeignKey
ALTER TABLE "memory_revisions" ADD CONSTRAINT "memory_revisions_memory_id_fkey" FOREIGN KEY ("memory_id") REFERENCES "memory_items"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memory_revisions" ADD CONSTRAINT "memory_revisions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "knowledge_chunks" ADD CONSTRAINT "knowledge_chunks_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "knowledge_documents"("id") ON DELETE CASCADE ON UPDATE CASCADE;

UPDATE "memory_items" SET "memory_type" = CASE "kind" WHEN 'ACTIVITY_TIME' THEN 'ROUTINE' WHEN 'SCHEDULE' THEN 'ROUTINE' WHEN 'AVAILABLE_MINUTES' THEN 'ROUTINE' WHEN 'ACTIVITY_LIKE' THEN 'PREFERENCE' WHEN 'ACTIVITY_DISLIKE' THEN 'PREFERENCE' WHEN 'FOOD_CONTEXT' THEN 'PREFERENCE' WHEN 'BARRIER' THEN 'BARRIER' WHEN 'HEALTH_EVENT' THEN 'EPISODE' ELSE 'FACT' END, "valid_from" = COALESCE("confirmed_at", "created_at"), "last_verified_at" = "confirmed_at", "source_ids" = CASE WHEN "source_id" IS NULL THEN ARRAY[]::TEXT[] ELSE ARRAY["source_id"::text] END;

ALTER TABLE "memory_items" ADD CONSTRAINT "memory_items_memory_type_check" CHECK ("memory_type" IN ('FACT','PREFERENCE','ROUTINE','BARRIER','GOAL','EPISODE','DERIVED'));
ALTER TABLE "memory_items" ADD CONSTRAINT "memory_items_privacy_scope_check" CHECK ("privacy_scope" IN ('PRIVATE','COACHING','SOCIAL'));
ALTER TABLE "memory_items" ADD CONSTRAINT "memory_items_conflict_state_check" CHECK ("conflict_state" IN ('NONE','CONFLICTING','SUPERSEDED'));
ALTER TABLE "knowledge_documents" ADD CONSTRAINT "knowledge_documents_lane_check" CHECK ("lane" IN ('A_PUBLIC_HEALTH','C_BEHAVIOR_STRATEGY'));
ALTER TABLE "knowledge_documents" ADD CONSTRAINT "knowledge_documents_review_status_check" CHECK ("review_status" IN ('CANDIDATE','DRAFT','REVIEWED','RETIRED'));
ALTER TABLE "knowledge_documents" ADD CONSTRAINT "knowledge_documents_reviewed_check" CHECK ("review_status" <> 'REVIEWED' OR ("reviewed_at" IS NOT NULL AND "reviewer" IS NOT NULL));
ALTER TABLE "memory_revisions" ADD CONSTRAINT "memory_revisions_change_check" CHECK ("change" IN ('PROPOSED','CONFIRMED','CORRECTED','PAUSED','RESUMED','DISMISSED','DELETED','SUPERSEDED','CONFLICT'));
CREATE INDEX "knowledge_chunks_embedding_idx" ON "knowledge_chunks" USING hnsw ("embedding" vector_cosine_ops);
CREATE INDEX "knowledge_chunks_text_trgm_idx" ON "knowledge_chunks" USING gin ("text_normalized" gin_trgm_ops);
