# Activity API

Existing verified Better Auth bearer session and current health_data_processing consent required for all routes. Summary endpoints and Today additionally require descriptive_summaries. Owner always derives from session; strict body schemas reject owner/source impersonation. Responses use existing private/no-store wrapper.

| Method / path | Contract |
|---|---|
| POST /api/me/activities | Stable UUID create,201; identical retry returns existing; different payload409 |
| GET /api/me/activities | date optional local ISO date, cursor optional owned UUID, limit1–50/default20, archived true/false/defaultfalse |
| GET /api/me/activities/:id | Owned detail, local-time preference and original UTC timestamps |
| PATCH /api/me/activities/:id | expectedVersion+reason and at least one field; transactional revisions; archive/restore via archived boolean |
| GET /api/me/activities/:id/revisions | Prior snapshots/reasons, newest version first |
| GET /api/me/activities/summary | Optional date, otherwise today in saved timezone |
| GET /api/me/activities/weekly | Optional date inside selected week, otherwise user's current week |
| GET /api/me/timeline | domain now accepts activity in addition to all/meal/glucose |
| GET /api/me/summaries/daily | Existing Nutrition top-level contract plus glucose and activity members |
| GET /api/me/today | Activity AVAILABLE with current summary and source-linked preview |

Synthetic create:

```json
{
  "id": "<runtime UUID>",
  "activityType": "walking",
  "startedAt": "<ISO timestamp with offset>",
  "durationMinutes": 30,
  "distanceKm": null,
  "steps": null,
  "reportedIntensity": "unknown",
  "source": "manual",
  "qualityStatus": "user_reported",
  "notes": null
}
```

Required id/type/start/duration. Types walking/cycling/running/strength/other. Duration integer1–1440; start is real,>=1900; derived end cannot exceed current server time plus5-minute clock tolerance. Client endedAt is rejected rather than independently trusted. Optional km0–1000/three decimals, steps integer0–1000000; null/omitted is unknown. Intensity unknown/light/moderate/vigorous; manual source only; quality user_reported or needs_review; nullable notes max2000. These bounds are technical guards, not exercise recommendations.

Detail includes id/type/startedAt/endedAt/durationMinutes, nullable distanceKm/steps, intensity/source/quality/note, version/archive, recordedAt/receivedAt/createdAt/updatedAt, localDate/localTime/endLocalDate/endLocalTime/timezone. Start+30minutes returns end exactly1800000ms later. Input timezone offsets are preserved semantically as instants, not a separate display-zone field.

PATCH example: `{"expectedVersion":1,"reason":"Correct duration","durationMinutes":45}`. Recalculates end, preserves omitted metrics/source/notes, stores prior state. Archive/restore uses version/reason plus archived true/false; no hard DELETE route. List returns items/details, nextCursorUUID|null and timezone.

Summary returns date/startDate/endDate(exclusive)/timezone/locale/firstDay, count/eligibleCount/reviewCount, durationMinutes|null, distanceKm and steps as `{value,knownSessions,totalSessions,coverage}`, days, activeDays, latest|null, analyticsState, computedAt, freshnessCURRENT, coverageStatusRECORDED_ONLY, source manual, attributionSTART_LOCAL_DATE, durationMethodSUM_REPORTED_SESSIONS and computationVersionactivity-reported-v1. Daily firstDay null/days length1; weekly firstDay7 for id-ID/days length7.

Eligible means active user_reported session. No eligible records→durationnull/INSUFFICIENT_DATA, not an assertion of inactivity. One or more→READY. Unknown optional totals staynull; partial totals retain coverage. Start-local-date attribution includes cross-midnight sessions wholly; overlapping sessions are summed independently. Weekly calendar dates use saved locale/timezone, not fixed168-hour windows. Corrections/archive/restore recompute on next read. No calories, inferred goals or medical conclusions.

Errors:400 invalid strict schema/date/source/numeric/body or invalid opaque timeline cursor;401 absent/inactive/unverified session;403 CONSENT_REQUIRED;404 owned record/cursor missing, including cross-user IDs;409 IDEMPOTENCY_CONFLICT/VERSION_CONFLICT;422 ACTIVITY_NOT_COMPLETED when merged correction would end in future; safe500 via existing wrapper. Sensitive payloads are not added to logs.

Bruno folder11 Activity extends the same collection/environment with20 ordered executable cases. Runtime sessionToken,otherSessionToken,restrictedSessionToken,newActivityId,eventTime; other owner has full consent, restricted health only. Full collection additionally needs newMealId/newGlucoseId. Run `bru run --env test` from collection root in Docker networkbeokay-test_default with runtime --env-var injection. Use fresh UUIDs/accounts for ordered version1→4 cases, and eventTime at least60minutes before execution. No tracked credentials. Actual results are recorded in [testing](../testing/activity.md).
