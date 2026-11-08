# Activity — design and UI/API contract

Slice4 design-first. Existing native `design/beOkay-ui.figcraft` extended with page4085 `12 — Activity`: Overview, Form, Detail, Week, States. Five 390×1120 frames; native CLI rendered overview and individual PNG handoff under design/activity-handoff. Actual render inspected before Flutter implementation. Same Inter, Ice Blue #C8D9E8, Off White #F6F8FA, Charcoal #171B20, Slate #788996 decorative, Steel #A8BDCE and White, with existing darker secondary text/focus/semantic tokens in Flutter. Spacious single-column editorial heading/charcoal feature, pill actions,24px cards and padding,44–48px controls; data does not use medical colors. No new photographs without verified asset permission. No claim of GUI MCP attach, user approval, editable responsive variants or pixel-perfect parity.

| Screen | Functional behavior | Endpoint |
|---|---|---|
| Today | Count/logged duration or honest empty; recent events link to source | GET /api/me/today |
| Shared Quick Record | Activity enabled; medication remains preview | /activities/new |
| Form | Type/start/duration; optional km/steps/intensity/note/review; end derived; save/errors/retry | POST /api/me/activities |
| History | Date/archive filters, source/quality, pagination, detail | GET /api/me/activities |
| Detail | Start/end/duration, optional metrics, source, provenance; correction/archive/restore/revisions | GET/PATCH /api/me/activities/:id; GET /:id/revisions |
| Weekly | Week previous/next/date; local-day selector, session counts/durations and data coverage; method/source details | GET /api/me/activities/weekly?date=YYYY-MM-DD |
| Daily summary | Source records, eligible/review count, null/partial optional totals | GET /api/me/activities/summary?date=YYYY-MM-DD |
| Timeline/Today preview | Three domains, actual occurrence time/source detail | Existing read model extended with activity |

Loading/empty/error/consent states, original input persistence on uncertain online save, conflict→reload and unsaved-change guard. No local-saved/synced success before durable offline work. No invented goals/progress percentages, calories or clinical conclusions. Weekly summary uses runtime locale first day: id-ID Sunday, saved timezone for local dates. Sessions crossing midnight are attributed wholly to start date; duration is summed session time, not deduplicated active time.

Responsive Flutter: scrollable SafeArea, wrap controls rather than dense grids, scalable text, keyboard-safe form. Week day selector wraps on narrow screens; seven-day values have textual equivalents and selected-day history link. Final widget/Appium/visual results recorded separately, not assumed from design.
