DROP TABLE IF EXISTS "knowledge_chunks";
DROP TABLE IF EXISTS "knowledge_documents";
DROP TABLE IF EXISTS "memory_revisions";
ALTER TABLE "memory_items" DROP CONSTRAINT IF EXISTS "memory_items_memory_type_check", DROP CONSTRAINT IF EXISTS "memory_items_privacy_scope_check", DROP CONSTRAINT IF EXISTS "memory_items_conflict_state_check", DROP COLUMN IF EXISTS "memory_type", DROP COLUMN IF EXISTS "source_ids", DROP COLUMN IF EXISTS "valid_from", DROP COLUMN IF EXISTS "last_verified_at", DROP COLUMN IF EXISTS "privacy_scope", DROP COLUMN IF EXISTS "conflict_state", DROP COLUMN IF EXISTS "superseded_by", DROP COLUMN IF EXISTS "paused_at", DROP COLUMN IF EXISTS "pause_reason";
ALTER TABLE "agent_runs" DROP COLUMN IF EXISTS "skill_id", DROP COLUMN IF EXISTS "skill_version", DROP COLUMN IF EXISTS "journey", DROP COLUMN IF EXISTS "iterations", DROP COLUMN IF EXISTS "fsm_state";
ALTER TABLE "agent_tool_calls" DROP COLUMN IF EXISTS "tier", DROP COLUMN IF EXISTS "iteration";
DELETE FROM "_prisma_migrations" WHERE "migration_name" = '20261113051241_p13_skills_knowledge_memory';
