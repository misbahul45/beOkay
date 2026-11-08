# Activity — data dictionary and intended invariants

Migration `20261108130338_activity`, generated and deployed on isolated PostgreSQL only. ActivitySession maps to activity_sessions, UUID PK/default gen_random_uuid and user_id FK to existing Better Auth Users UUID. Fields: activity_type TEXT(walking,cycling,running,strength,other); started_at/ended_at TIMESTAMPTZ(6); duration_minutes INTEGER 1–1440; distance_km NUMERIC(10,3) nullable0–1000; steps INTEGER nullable0–1000000; reported_intensity TEXT(unknown,light,moderate,vigorous); source TEXT manual; quality_status TEXT(user_reported,needs_review); notes TEXT nullable/max 2000; version positive; create_hash 64 chars; archived_at nullable; recorded_at/received_at/created_at/updated_at TIMESTAMPTZ(6).

CHECK ensures enumerated states, nonnegative known optional values, exact end=start+duration interval, earliest 1900 timestamp, positive bounded duration, hash/version/note constraints. Request validation additionally rejects future start/end beyond 5 minute tolerance, fractional minutes and unsupported source/body owner. Optional unknown remainsNULL; explicit0 is retained. End is server-derived, not an independent mutable field.

Index(user_id,started_at DESC,id DESC). RecordRevision gains nullable activity_id FK/unique(activity_id,version); replace existing exclusive-source CHECK with exactly one of meal_id/glucose_id/activity_id. Existing revisions remain valid. No duplicate identity, writable universal timeline or persistent analytics/sync table.

Owner-scoped API derives identity from verified session. Updates/revisions/audit in one transaction with expectedVersion. Stable create UUID/hash prevents duplicate retry. Soft archive/restore retain source and correction history. Queries filter start-local date using PostgreSQL IANA bounds. Weekly first day from Intl.Locale week info; summaries recompute from eligible records on read. No unique-active-time claim for overlapping reported sessions.

Migration deployment, generation and backend typecheck passed. Prisma drift contains only known UUID-default noise on four auth tables. Dev/production data must not be migrated during this slice.
