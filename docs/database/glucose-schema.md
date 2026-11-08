# Glucose data dictionary and migration

Migration: `20261108110400_glucose`. Verified on disposable PostgreSQL test services only; not applied to development or production as part of this delivery.

| Column | PostgreSQL type | Meaning |
|---|---|---|
| id | UUID PK, gen_random_uuid | Stable observation identity; also accepts client UUID for idempotency |
| user_id | UUID FK users, NOT NULL | Better Auth owner |
| source | TEXT | `manual_glucometer` only |
| source_record_id | TEXT nullable | Reserved, must remain NULL for current manual source |
| measurement_type | TEXT | `capillary_blood` only |
| original_value | NUMERIC(12,4) | Positive user-entered source measurement |
| original_unit | TEXT | `mg/dL` or `mmol/L` |
| value_mg_dl | NUMERIC(16,7) | Canonical value; exact product with factor 18.016 |
| measured_at | TIMESTAMPTZ(6) | Actual occurrence time supplied by user |
| recorded_at / received_at / created_at | TIMESTAMPTZ(6) | Server durable capture/receipt/creation time |
| meal_context | TEXT | Explicit user choice; never inferred from nearby meals |
| quality_status / quality_flags | TEXT / TEXT[] | `user_reported` plus empty flags, or `needs_review` plus `user_flagged` |
| notes | TEXT nullable | Optional note, max 2000 characters |
| version | INTEGER | Positive optimistic revision counter |
| create_hash | TEXT | Hash of original validated create request, not health data in audit logs |
| archived_at | TIMESTAMPTZ(6) nullable | Archive marker; active summaries/history exclude it |
| updated_at | TIMESTAMPTZ(6) | Last persisted correction |

CHECK constraints enforce source/type, unsupported external ID rejection, valid unit/context/status, positive original and canonical 1–2000, exact canonical conversion, flag/status consistency, version/hash length, earliest timestamp and note size. Original input validation also rejects more than four decimals, malformed dates and timestamps beyond the five-minute input tolerance.

Index: `(user_id, measured_at DESC, id DESC)` for owner/time history. The source and owner are never taken from a body user ID. All Prisma/SQL access remains owner-scoped. No external import uniqueness is activated because there is no supported external source.

`record_revisions` is extended with nullable `glucose_id` FK and nullable existing `meal_id`. CHECK `num_nonnulls(meal_id, glucose_id)=1` ensures exactly one domain source; unique `(glucose_id, version)` preserves previous versions independently from meal revisions. Existing meal rows retain their FK and uniqueness. Foreign keys cascade only with owner/source deletion according to existing schema policy. Archive/restore do not delete revisions.

Relations: Users 1→N GlucoseObservation; GlucoseObservation 1→N RecordRevision; RecordRevision targets exactly one MealLog or GlucoseObservation. The existing auth model is extended only by a back-relation. No duplicate users, universal writable events, daily/weekly summary tables or sync tables are introduced.

Schema drift verification must show only the repository's known gen_random_uuid defaults on four auth tables. SQL CHECK constraints intentionally live in migration SQL because Prisma schema does not express them.
