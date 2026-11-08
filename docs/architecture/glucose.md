# Glucose — Slice 3 online

`features/glucose` owns schema validation, precise conversion, repository, service, routes and observation revisions. Existing Better Auth `authenticated` supplies the verified session user ID; `health_data_processing` consent is required for every observation endpoint. Descriptive reads additionally require `descriptive_summaries`. No new identity or authentication mechanism is introduced.

## Source and display semantics

Only self-reported manual capillary-blood glucometer readings are accepted. A saved reading is an observation copied by the user, not a device integration or verified clinical interpretation. `originalValue` and `originalUnit` preserve the entered measurement. The canonical `valueMgDl` uses Prisma Decimal and the existing project factor **18.016**, without display rounding. Display conversion rounds mg/dL to whole numbers and mmol/L to one decimal; when display and source units match, the original precision is retained. Changing preferences does not write observations or create revisions.

The technical canonical input/storage domain is 1–2000 mg/dL, with up to four original decimal places. This is an application guard, not a clinical target or interpretation. A user can flag an observation `needs_review`; it stays visible with `user_flagged` provenance and is excluded from aggregate values. No ranges, diagnosis, treatment instructions, time-in-range, interpolation or causal claims are produced.

## Transactions and corrections

Creation uses a client-generated UUID plus a server hash of the validated input. Retrying the same UUID/payload returns the existing record; different payloads conflict. Concurrent retries are resolved by the primary key and hash check. Ownership is always session-derived.

PATCH requires `expectedVersion` and a reason. Owner/version-scoped update, prior-state revision and metadata-only audit are one transaction. Sparse patches preserve all omitted fields; defaults do not clear notes/context or change units. Archive and restore are versioned corrections. There is no hard-delete endpoint. Conflicts return 409 and require review/reload; no last-write-wins overwrite.

## Read models

History uses descending `(measured_at, id)` keyset pagination, with owner-scoped cursor lookup, date and archive filters. Local date boundaries are computed by PostgreSQL using saved IANA timezone, including DST days. Read transactions use RepeatableRead.

Glucose daily summaries are computed from current active source rows on each read: counts, latest observation, review/eligible counts, and arithmetic mean/minimum/maximum after at least two eligible observations. Below that threshold these aggregate values remain null, with `INSUFFICIENT_DATA`; otherwise `READY`. Every result includes method version, timestamp, source and freshness. Corrections therefore affect the next read without a stale persistent projection. No daily_summaries/weekly_summaries table or background analytics engine is claimed here.

Today composes current Nutrition/Glucose daily models and the first five same-day timeline events. Timeline is now a separate feature querying a UNION of meal/glucose source records, ordered by occurrence time, domain and ID; its opaque cursor preserves tie ordering. It supports a legacy owner-scoped meal UUID cursor for compatibility. It is a read model, not a universal writable event table. The daily summary route moved from Nutrition to Insights and retains Nutrition's existing top-level response with a `glucose` member.

## Flutter

`features/glucose/{data,application,presentation}` uses existing ApiClient, Riverpod, go_router, Inter/theme tokens and form controls. New forms await preferences, default to the preferred unit, and clearly distinguish changing the input unit from converting a value. Edit forms always load original value/unit. Time selection is explicitly in device timezone; history/display uses server-supplied preference timezone.

Shared `AccountScopedRepository` captures the bearer token before writes and rejects writes when its owning provider/account is obsolete. Nutrition uses the same implementation. Record UUID generation, reason dialog and health cards/errors are shared. Account changes dispose dependent providers; no health records are cached durably on the client in this slice.

Successful mutations invalidate detail, history, daily and Today providers. Validation errors keep input editable; uncertain network/server outcomes freeze the submitted payload for retry, and version conflicts require reload. Forms guard unsaved changes. History shows only actual points on the current paginated page, without connecting lines or clinical ranges, alongside the full textual observation list and quality/source labels.

## Limits

This is an online vertical slice. Durable drafts, offline queue, sync operations, conflict review across devices, four primary tabs, complete Log/Insights screens, weekly summaries and later domains remain separate P0 slices. External CGM/device sources and all P1 features are inactive. Consent policy text remains a project draft requiring its own review.
