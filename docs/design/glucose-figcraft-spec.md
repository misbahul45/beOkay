# Glucose — native FigCraft design and handoff

Editable source: `design/beOkay-ui.figcraft`, existing project, page **4022 — 11 — Glucose**. Verified by native `figcraft-cli info`; five top-level frames:

| ID | Frame | Canvas |
|---|---|---|
| 4023 | Glucose — Empty | 390×1000 |
| 4032 | Glucose — Form | 390×1000 |
| 4052 | Glucose — History | 390×1000 |
| 4062 | Glucose — Detail | 390×1000 |
| 4071 | Glucose — States | 390×1000 |

The page was created before UI implementation using the native headless FigCraft command engine, then rendered and inspected. Desktop MCP attach remains unreliable from the earlier slice; no successful GUI editing session or user design approval is claimed. No new Figma project was substituted.

Reviewable [overview](../../design/glucose-overview.png) and individual PNG exports in `design/glucose-handoff/`. The editable file contains the original pages plus Nutrition and Glucose; responsive variants and pages 12–19 are not claimed complete. Design frames specify hierarchy and states, not a pixel-perfect copy of every dynamic Flutter state.

Reuse Inter, existing semantic/focus tokens and colors: Ice Blue #C8D9E8, Off White #F6F8FA, Charcoal #171B20, Slate Gray #788996, Steel Blue #A8BDCE, White #FFFFFF. Small secondary text uses the darker accessible text token rather than decorative slate. Padding 20–24, rounded 20–24 cards, pill actions and 48px controls. Glucose is data-led; no photographs or clinical colors used as decoration.

## Screen and API contract

| Entry / screen | Interaction and state | API |
|---|---|---|
| Today glucose card | Latest actual reading/time/source/review label, or honest empty message; record/history actions | GET /api/me/today |
| Shared Quick Record | Glucose opens form; Activity/Medication stay disabled previews | Existing launcher → /glucose/new |
| New observation | Wait preferences; numeric/unit, time, explicit context, optional review flag and note; pending save/error/retry | POST /api/me/glucose |
| History | Date and archive filters, keyset next/previous, actual point chart, source-linked cards, daily coverage/method | GET /api/me/glucose; GET /api/me/glucose/summary |
| Detail | Display/original values, unit/source/type, provenance, quality, note, version, correction/archive/restore | GET/PATCH /api/me/glucose/:id |
| Correction history | Prior value/time, reason and previous version | GET /api/me/glucose/:id/revisions |
| Today event preview | Meal/glucose occurrence order and navigation to original record | Today timeline read model |
| Display settings | Existing unit preference; does not mutate original observations | Existing preferences API |

Loading, empty, partial/insufficient data, consent-required, failure, conflict and archive states are functional. Unknown glucose is never shown as zero. No offline-success/sync badge is shown because durable offline storage is a later slice. Uncertain online writes preserve the same payload and record ID for retry.

Charts show separated observed points with time and selected-unit axes; hollow points identify user-flagged observations. Textual cards provide equivalent values, source, quality, timestamps and detail action. The chart explicitly covers only the current page. No line interpolation, target shading or CGM-like curve.

Flutter is scrollable/SafeArea-aware; no fixed-height health content except the graph plotting area. Keyboard handling and entered source-unit correction were inspected on Android; chart and Today have automated 320px/text-scale-2 layout checks. Full screen-reader, iOS, physical device and all-screen responsive certification are not claimed.

Replay exports: `figcraft-cli export design/beOkay-ui.figcraft --page '11 — Glucose' --out design/glucose-handoff --format png`. Do not regenerate the entire design project or replace existing tokens.
