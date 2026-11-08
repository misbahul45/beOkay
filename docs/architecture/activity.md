# Activity — Slice 4 online

Activity owns its routes, Zod contracts, service, repository and model. It reuses verified Better Auth sessions, current-purpose consent and existing owner UUID. No new identity, password, theme, state-management or API architecture.

Sessions are completed, manually reported activities: walking, cycling, running, strength or other. The source start timestamp and integer duration determine end time on the server and in the form preview. Optional km/steps are nullable, including explicit zero only when supplied. Intensity is self-reported, not calculated. Needs-review records remain visible and are excluded from aggregate totals. No calories, GPS, heart-rate measurements, clinical advice or inferred goal completion.

Create uses stable client UUID plus hash of validated input; repeated identical and concurrent retries return the existing session. Different payload reuse conflicts. Corrections require expectedVersion/reason and atomically update owner-scoped source, store prior RecordRevision and metadata-only audit. Archive/restore are versioned changes. Prisma and database CHECKs enforce time/duration, source, state and numeric invariants.

History is owner-scoped start-time/ID keyset pagination with local-date/archive filters. Daily/weekly reads use current active source rows in RepeatableRead. Week boundaries use the user's locale via Intl.Locale.getWeekInfo and local dates in saved IANA timezone. Current supported locale id-ID starts Sunday; en-GB Monday is covered in domain tests. PostgreSQL converts calendar bounds to instants, including 23/25-hour days.

Every session is attributed wholly to its start-local date, including cross-midnight sessions. Reported durations are summed per eligible session; overlapping sessions are not deduplicated into unique active minutes. Count0 proves no matching records, not physical inactivity. No eligible duration returns null; optional totals expose knownSessions/totalSessions and UNKNOWN/PARTIAL/COMPLETE. Responses include source, method version, coverage, timestamp, analytics eligibility and freshness. Corrections affect the next read without stale persisted summaries.

Today and daily composite include Activity. Unified timeline UNION reads meal/glucose/activity source tables, with occurrence/domain/ID ordering, existing cursor compatibility and no duplicate writable event table. Flutter Today renders type/duration/source and navigates to the original session. Quick Record uses the existing launcher. No full Log/Insights tab or global weekly analytics is claimed here.

Flutter feature has data/application/presentation, shared account-captured writes, API/consent/preference dependencies, reusable cards/form controls and editorial layout. Forms guard unsaved changes and freeze uncertain payloads for retry; conflicts require reload. Successful writes invalidate detail, list, daily, weekly and Today. History/detail/weekly provide loading, empty, consent and retry states. Local input time is explicitly device timezone; output follows preferences. Weekly day selection links dated history.

Offline durable storage/sync, goals, medication and P1 remain later slices. Online API idempotency does not imply offline queue support. Composite Today is not a single cross-domain transaction. No production performance or complete accessibility certification is claimed.
