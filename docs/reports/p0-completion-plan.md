# P0 completion — active execution plan

Status IN_PROGRESS. User now requests all P0 completed without per-feature review stops. Preserve visible host Pixel_4 and isolated API, existing uncommitted Activity documentation. No git add/commit/push, destructive resets, auth rewrite or P1 expansion. Backend execution only Docker; Flutter host allowed; credentials runtime/temp only. Shared memory/plan MCP unavailable: this file is durable checkpoint and assignment record.

Audit baseline: verified Nutrition/Glucose/Activity online with source corrections/revisions and three-domain Today/timeline, Better Auth/consent/onboarding/preferences intact. Missing Medication/Goals, full four-tab navigation/Log/Insights, persisted daily/weekly projection freshness, durable local tracking queue/sync/conflict/account privacy. Existing test evidence15 backend/264 expectations,52 Flutter,57 Bruno; rerun after integration.

Execution axes and merge order:

1. Root: shared schema/migrations/transaction boundary, Medication full vertical slice, global router/Today/Profile integration, native FigCraft designs and final verification.
2. Goals worker: only server/features/goals, app/features/goals, its own tests/docs/Bruno; propose Prisma fragment, root integrates schema. No router/Today/global schema edits.
3. Offline worker: only app/features/sync and its tests/docs; account-isolated encrypted local store, durable operation queue, retry/conflict/restart recovery/cache, UI status. Provide explicit integration hooks; root integrates existing repositories/forms. No global providers/router/auth edits or new dependency without coordination.
4. Read-model worker: server/features/timeline and insights, app/features/timeline and insights, own tests/docs/Bruno; full Log filters/details and descriptive daily/weekly source/coverage/freshness. Root integrates routes/Today/shared schema. Wait for design-ready checkpoint before UI.
5. Independent verification worker after a slot frees: security/requirements/test review with bounded read/test tools, findings and evidence; no production edits unless root assigns a concrete fix.

Nonoverlapping writers; deterministic merge: security/correctness first, root schema/transaction helpers → domain services → read models → offline hooks → navigation/Today → full tests/Appium/Bruno. Root cross-checks each deliverable against source/tests; unresolved contradictions/incomplete evidence remain incomplete. No claim of P0 completion until acceptance matrix and actual checks are recorded.

Sequence: audit/plan/contracts → remaining native FigCraft pages13–19 and spec → backend red tests/schema/services + independent Goals/backend/offline work → full UI → source invalidation/projections → atomic idempotent sync → durable offline form/history integration → account switching/consent and negative checks → unit/integration/widget/E2E/visual/Bruno/build → final report.

Contracts for workers are in docs/architecture/p0-integration-contracts.md. Each worker must preserve existing patterns, explicit validation, owner/consent checks, revision reason/version and no unsupported clinical interpretation. Tools allowed: code graph/read/search/apply_patch, local filesystem scratch, Docker backend tests/typecheck, Flutter/Dart tests/analyze, native FigCraft read/render if needed. No external communication/publication/git mutations. Scope failures are reported with evidence, never hidden by skipping tests.

Next action: shared integration contracts and editable designs, then start independent workers. Rollback is review/revert only owned changes by user; migrations only disposable DB and no automatic shutdown of requested GUI.
