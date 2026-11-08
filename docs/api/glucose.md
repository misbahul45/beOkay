# Glucose API — Slice 3

All private routes use existing verified Better Auth bearer sessions. User identity comes from the session, never a body/query owner. Every route needs current `health_data_processing`; summaries/Today also need `descriptive_summaries`. Responses are private/no-store using existing HTTP wrappers. Only manual capillary-blood glucometer entry is supported.

| Method / path | Request / behavior |
|---|---|
| POST /api/me/glucose | Create, 201; same UUID/input retry returns existing record; changed input/UUID reuse → 409 |
| GET /api/me/glucose | `date?` ISO local date, `cursor?` owned UUID, `limit` 1–50 default20, `archived` true/false defaultfalse |
| GET /api/me/glucose/:id | Owned detail, current display preference |
| PATCH /api/me/glucose/:id | expectedVersion, reason, at least one changed field; 200 or 409 version conflict |
| GET /api/me/glucose/:id/revisions | Previous version snapshots and reasons, newest first |
| GET /api/me/glucose/summary | Optional ISO local `date`, otherwise today in saved timezone |
| GET /api/me/timeline | Meal+glucose source read model: `domain=all|meal|glucose`, `date?`, opaque `cursor?`, limit1–30 default20, archived true/false |
| GET /api/me/summaries/daily | Existing top-level Nutrition daily contract plus `glucose` summary, same optional date |
| GET /api/me/today | Nutrition and Glucose AVAILABLE; Activity/Medication unavailable; first five source-linked same-day timeline events |

## Input and examples

Synthetic create input (UUID/time must be generated at runtime):

```json
{
  "id": "<runtime UUID>",
  "originalValue": 5.5,
  "originalUnit": "mmol/L",
  "measuredAt": "<ISO timestamp with offset>",
  "mealContext": "after_meal",
  "source": "manual_glucometer",
  "measurementType": "capillary_blood",
  "qualityStatus": "user_reported",
  "notes": null
}
```

Required: id, positive finite originalValue (up to four decimals), originalUnit and measuredAt. Canonical value must be 1–2000 mg/dL; this is a technical input guard, not a health target. Measurement timestamp must be real, >=1900 and no more than five minutes ahead of current server time. Notes nullable/max2000. Strict schemas reject unknown fields such as userId or sourceRecordId. CGM/external types are rejected.

Contexts: fasting, before_meal, after_meal, bedtime, other, unknown (default). Source/type defaults are manual_glucometer/capillary_blood. Quality defaults user_reported; needs_review adds server-controlled user_flagged and excludes the reading from averages. No context is inferred from meals.

With a mg/dL display preference, the synthetic input above returns these representative fields:

```json
{
  "originalValue": 5.5,
  "originalUnit": "mmol/L",
  "valueMgDl": 99.088,
  "displayValue": 99,
  "displayUnit": "mg/dL",
  "converted": true,
  "source": "manual_glucometer",
  "measurementType": "capillary_blood",
  "qualityStatus": "user_reported",
  "qualityFlags": [],
  "version": 1,
  "archivedAt": null
}
```

Full detail also has id, measuredAt, localDate/localTime/timezone, context/notes, recordedAt/receivedAt/createdAt/updatedAt. The entered unit/value are preserved. Canonical multiplication uses Decimal ×18.016; converted display mg/dL rounds to integer, mmol/L to one decimal. Display in the original unit retains original precision. A preference change does not increment observation version.

Correction example: `{"expectedVersion":1,"reason":"Correct entry","originalValue":6.1}`. Omitted fields remain unchanged. Archive/restore: same version/reason fields plus `archived:true|false`. Every successful PATCH records previous state transactionally, increments version, and affects the next summary/timeline read. No DELETE route.

List response: `{items:[detail...], nextCursor:UUID|null, timezone, displayUnit}`. Date/archive filters compose. Timeline response has `{supportedDomains:["meal","glucose"],timezone,nextCursor,items}`; each event includes domain, recordId, occurredAt, local date/time and domain fields. Opaque cursors preserve descending event-time/domain/ID tie order; historical owner-scoped meal UUID cursors remain accepted. Cursor contents confer no authorization.

## Analytics contract

Summary returns date/timezone/displayUnit, count, eligibleCount, reviewCount, latest/detail|null, mean/minimum/maximum|null, analyticsState, computationVersion=`glucose-descriptive-v1`, computedAt, freshness=`CURRENT`, source and measurementType. Latest may be user-flagged and retains its label. Aggregates require at least two active, user_reported readings; otherwise null/INSUFFICIENT_DATA. Empty means count0/latestnull, not glucose0. Mean is arithmetic over canonical measured values; conversion is only for display. No unobserved values, targets, TIR or diagnosis.

These summaries are computed on read; source correction/archive/restore is reflected on the next read. No persistent daily/weekly projection, background computation, contextual inference or offline sync is implemented by these endpoints. Today's overall analyticsState remains NOT_AVAILABLE for the broader unfinished Insights feature; the Glucose summary has its own eligibility state.

## Errors and Bruno

400: malformed/strict schema, invalid numeric/unit/source/context/date, empty patch or invalid opaque cursor. 401: absent/inactive/unverified session per existing guard. 403 CONSENT_REQUIRED: missing/withdrawn current purpose. 404: owned record/cursor not found, including another user's ID. 409 IDEMPOTENCY_CONFLICT or VERSION_CONFLICT: duplicate ID with different input or stale correction. 422 GLUCOSE_VALUE_OUT_OF_DOMAIN: merged correction outside canonical guard. Safe 500 uses existing error wrapper; no sensitive payload logging added.

Bruno folder `10 - Glucose` extends the existing collection/environment with 18 executable cases. Runtime variables: sessionToken, otherSessionToken (different owner), restrictedSessionToken (health consent only), newGlucoseId and eventTime. The full collection also needs newMealId. Never persist credentials in tracked environment files.

From collection root inside the isolated Docker network: `bru run --env test` with those runtime `--env-var` values. Run on fresh fixtures because correction/archive tests depend on versions1→4. Actual results and fixture setup are in [testing](../testing/glucose.md).
