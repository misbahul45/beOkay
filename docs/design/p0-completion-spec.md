# P0 remaining screens — design-first handoff

Native existing FigCraft project extended before UI work with pages13 Medication,14 Goals,15 Unified Timeline,16 Insights,17 Offline/System,18 Responsive Variants,19 Developer Handoff. Editable frames and actual native rendered overviews in design/*-p0-overview.png. No replacement design tool, no GUI attach/user approval/pixel-perfect claim.

Reuse Inter and established IceBlue C8D9E8, OffWhite F6F8FA, Charcoal171B20, Slate788996 decoration, SteelA8BDCE, White. Small text uses darker slateText/566673; existing semantic tokens, focus and48px controls. Charcoal editorial entry cards, white rounded data/forms, pill actions,20–24px padding, scrollable SafeArea with keyboard-safe forms and text scaling. No unlicensed photography or unsupported devices/notifications/ML.

Screen contract: Medication list/setup/intake/history/states → /api/me/medications + schedules/intakes; Goals list/setup/detail/checkin/states → /api/me/goals + checkins; Log filters/date/pagination → /api/me/timeline with original domain links; Insights daily/weekly/source details → summary endpoints; Sync queue/status/conflict/privacy → local account store + /api/me/sync operations/status. Shared bottom tabs TODAY|LOG|INSIGHTS|PROFILE and one Quick Record launcher. Profile links medication/goals/privacy/local-data controls.

Medication copies reported instructions, never recommends dose. Schedule and actual intake separate; unconfirmed is never assumed taken/missed. Goals manual or source-derived, explicit target/frequency/period and no glucose achievement score. Insight cards descriptive, source/coverage/version/freshness, no unsupported clinical interpretation. Offline save state distinct from server sync; cached summaries stale/unavailable; account/consent protects cache and queue. Conflict requires review before overwrite.

Loading, empty, error, consent, success, stale/offline and conflict states belong to real capabilities, not decoration. Responsive variants320/600 use same components; controls wrap and dense information stays readable. Native renders are reviewable plans; actual Flutter/widget/Appium visual validation recorded separately.

DESIGN_READY: backend/data/tests and new UI may proceed using these frames/spec. Root will independently inspect renders and final screenshots and correct issues before delivery.
