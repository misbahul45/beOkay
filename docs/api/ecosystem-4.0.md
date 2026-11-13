# API 4.0 — endpoint baru dan berubah

Semua endpoint di bawah `/api/me/*` butuh sesi (401 tanpa sesi) dan dibatasi `user_id` dari sesi. Koleksi Bruno: [`bruno/20 - Ecosystem 4.0`](bruno/20%20-%20Ecosystem%204.0/). Arsitektur: [`../architecture/beokay-4.0-ecosystem.md`](../architecture/beokay-4.0-ecosystem.md).

## Berubah

| Endpoint | Perubahan |
|---|---|
| `GET /api/consent-policies/current` | versi `1.1`; tujuan opsional baru `device_data_coaching`, `social_outcomes_memory` |
| `PUT/PATCH /api/me/health-profile` | field opsional `riskStatement` (`prediabetes_told`, `at_risk_told`, `none`, `undisclosed`, atau `null`); 422 `RISK_STATEMENT_REQUIRES_NO_DIAGNOSIS` bila diagnosis diisi. Respons menambah `riskStatement` dan `journey { value, label, source, setAt }` |
| `GET /api/education/modules`, `GET /api/education/modules/:key` | difilter jalur pengguna; respons daftar menambah `journey` dan `items[].journeys`; detail modul jalur lain = 404 |
| `POST /api/me/device-import` | item `steps`, `weights`, `glucose`, `sleep` menerima `dataOrigin` opsional (nama paket, `^[A-Za-z0-9_.]{1,200}$`) |
| `POST /api/me/activities/import` | sesi menerima `dataOrigin`, `recordingMethod` (`automatic`, `active`, `manual`, `unknown`), `device` (`watch`, `phone`, `ring`, `scale`, `chest_strap`, `fitness_band`, `head_mounted`, `unknown`) opsional |
| `GET /api/me/memories` | menambah `paused[]` dan `conflicts[]`; butir menambah `memoryType`, `confidence`, `sourceIds`, `validFrom`, `lastVerifiedAt`, `privacyScope`, `conflictState`, `supersededBy`, `paused`, `pausedAt`, `pauseReason` |
| `GET /api/me/agent/tools` | 11 alat, masing-masing dengan `tier: "READ_ONLY"` |
| `GET /api/me/agent/runs/:id` | `events` dapat memuat `FSM_PATH` dan `FSM_DECISION` |
| `POST /api/me/conversations/:id/messages` | rute baru `SLEEP`, `EDUCATION`; `SUPPORT` menambah part `strategy`; part baru `evidence { certainty, items[] }`; `basis` dapat memuat `certainty`, `skill { id, runId, fsm }`, `secondarySkills`, `denial`. Jalur `UNDETERMINED` mendapat penolakan beralasan untuk skill saran |
| `POST /api/me/interventions/evaluate`, `GET /api/me/interventions` | `decisionV3` (`INTERVENE`, `DEFER`, `ASK_FOR_CLARIFICATION`, `WITHHOLD`, `NO_INTERVENTION`); alasan `WITHHOLD:<SAFETY_HOLD|USER_UNWELL|LOW_ENERGY_REPORTED|DATA_UNRELIABLE>`; `policyVersion` `jitai-policy-v3` |
| `GET /api/me/export` | menambah `memoryRevisions` |

## Baru

| Endpoint | Isi |
|---|---|
| `GET /api/me/journey` | `{ journey, label, description, source, assumed, setAt, capabilities }` |
| `GET /api/me/today/next-action` | `{ version, flow[], journey, today, action { kind, step, spark, title, body, target, ref, source }, progress { scoreVersion, week, personalBest, returnAfterBreak } }` |
| `GET /api/me/progress/peers` | butuh consent `challenge_participation` (403). `{ version, band, comparable, groupSize, half, note }`; tanpa nama, tanpa nilai kesehatan; `comparable=false` bila kelompok < 5 |
| `GET /api/me/devices/status` | `{ version, window, permissions, usedForCoaching, lastSyncAt, origins[], signals[], days{steps,sleep,workouts}[], notice }` |
| `POST /api/me/memories/:id/pause` | jeda ingatan aktif; 404 bila bukan milikmu |
| `POST /api/me/memories/:id/resume` | lanjutkan; 403 bila memori/consent tidak aktif |
| `GET /api/me/memories/:id/history` | riwayat revisi |

## Contoh

```json
GET /api/me/today/next-action
{
  "version": "next-action-v1",
  "flow": ["TODAY","NEXT_ACTION","CONFIRM","PROGRESS","REFLECTION","INSIGHTS","CHALLENGES"],
  "journey": "PREVENTION",
  "today": "2026-11-13",
  "action": { "kind": "CONFIRM_RECOMMENDATION", "step": "CONFIRM", "spark": "AWAITING_CONFIRMATION", "title": "Ada pilihan menunggu persetujuanmu", "body": "Tidak ada yang disimpan sebelum kamu memilih.", "target": "COACH", "ref": "<recommendationId>", "source": "agent_recommendation" },
  "progress": { "scoreVersion": "score-v2", "week": { "activeDays": 1, "deviceDays": 1, "effort": 1, "selfProgressBonus": 0, "total": 1 }, "personalBest": { "best7DayActive": 1, "longestStreak": 1 }, "returnAfterBreak": { "returned": false, "gapDays": null } }
}
```

Contoh bersifat sintetis.
