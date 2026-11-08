# Nutrition — execution checkpoint

Status: IN_PROGRESS. Scope: Slice 2 only; stop for user review after verification.

Plan: (1) native FigCraft design/handoff; (2) red tests; (3) Prisma schema/migration with CHECK constraints; (4) authenticated, consent/owner-scoped catalog and meal APIs, immutable nutrition snapshots, optimistic corrections/revisions, archive; (5) Flutter form/history/detail and Today integration; (6) meal timeline and uncached daily read model; (7) unit/integration/widget/Bruno/build verification; (8) final report.

Dependencies follow that order. No further approval needed for local reversible work. No git add/commit/push. Rollback: review diff and revert only this slice's changes; migrations run only on disposable test DB. Existing working tree was clean before implementation.

FigCraft desktop attach completed handshake but document requests timed out because the window was not drawing. Native headless FigCraft CLI uses the same command engine; editable source and rendered preview will be verified before UI implementation. No design approval on behalf of the user is claimed.

Data decisions: no invented nutrient values or seed catalog. Users may add a personal food with source/estimate labels and nullable per-100g nutrients; free-text meal items remain unknown unless defensible grams and nutrients exist. Historical item snapshots survive catalog updates and quantity corrections. Meals archive rather than hard-delete. Corrections require expected version and reason; previous state is retained transactionally. Daily/Today values are computed from current source rows on read, avoiding stale persistent projections in this slice. Full cross-domain summaries/offline sync remain later slices.

Next action: finish FigCraft native design, then implement red tests and Nutrition persistence.
