# Referensi Endpoint API

> Daftar lengkap rute yang terdaftar di `server/src/server.ts` (sumber: `*.routes.ts` tiap modul), diaudit 10 November 2026. Total: **±121 kombinasi metode+path** (+ sub-rute `/api/auth/*` milik Better Auth). Dokumen `docs/api/{activity,glucose,nutrition}.md` lama merinci contoh payload tiga domain pertama; dokumen ini mencakup semuanya.
> Sebagian besar kontrak payload didefinisikan oleh skema Zod di `server/src/features/<modul>/*.schema.ts` — itulah rujukan nama dan batas bidang yang tepat.

## 1. Konvensi umum

| Hal | Aturan |
|---|---|
| Basis URL | dev `http://127.0.0.1:3000` (`API_HOST_PORT`); prod di balik reverse proxy HTTPS |
| Autentikasi | `Authorization: Bearer <token>`. Token = header respons `set-auth-token` pada sign-in. Semua `/api/me/*` dan `/api/foods/*` mensyaratkan sesi **dan email terverifikasi** (`401 UNAUTHENTICATED`) |
| Badan | JSON `application/json` (maks 64 KB), skema `.strict()` → bidang tak dikenal ditolak `400 VALIDATION_ERROR`. Pengecualian: `scan/*` menerima byte gambar mentah (maks 1,5 MB) |
| Galat | `{"error":{"code","message","requestId","details?"}}`; header `X-Request-Id` selalu ada |
| Kursor | `?cursor=<uuid>&limit=1..50` (default 20); respons `{items, nextCursor}`. `timeline` memakai kursor `base64url` |
| Filter | `?date=YYYY-MM-DD` (tanggal lokal menurut zona pengguna), `?archived=true|false` |
| Idempotensi | `POST` pencatatan menerima `id` UUID dari klien; isi sama → baris lama, isi beda → `409 IDEMPOTENCY_CONFLICT` |
| Koreksi | `PATCH` wajib `expectedVersion` + `reason` (kecuali tabel yang disebut); `409 VERSION_CONFLICT` bila versi berubah |
| Status | `201` untuk pembuatan, `200` untuk lainnya; `202` untuk `ml/warmup` dan `agent/runs?async=1`; `429` untuk rate limit |

Kolom **Consent**: `H` = `health_data_processing`, `S` = `descriptive_summaries`, `A` = `personalized_ai`, `—` = tidak ada. Tanpa consent yang dibutuhkan → `403 CONSENT_REQUIRED` `{details:{purpose}}`.

## 2. Publik

| Metode | Path | Keterangan |
|---|---|---|
| GET | `/health` | `{status:"ok"|"degraded", db}`; `503` bila DB tak terjangkau |
| GET | `/api/consent-policies/current` | kebijakan consent aktif (versi, tujuan, dampak penarikan) |
| GET | `/auth/verified` | halaman HTML hasil verifikasi email |
| GET | `/auth/reset-password?token=` | halaman HTML formulir reset sandi |

## 3. Autentikasi — `/api/auth/*` (Better Auth)

Dikelola pustaka; rute yang dipakai aplikasi (terverifikasi dari `auth_repository.dart`):

| Metode | Path | Catatan |
|---|---|---|
| POST | `/api/auth/sign-up/email` | tidak masuk otomatis; mengirim email verifikasi |
| POST | `/api/auth/sign-in/email` | menolak bila email belum terverifikasi; kembalikan token di `set-auth-token` |
| GET | `/api/auth/get-session` | |
| POST | `/api/auth/sign-out` | |
| POST | `/api/auth/send-verification-email` | |
| POST | `/api/auth/request-password-reset` | |
| POST | `/api/auth/reset-password` | token berlaku 1 jam; mencabut semua sesi |
| POST | `/api/auth/change-password` | |
| GET | `/api/auth/list-sessions` · POST `/api/auth/revoke-other-sessions` | |

Rate limit (per menit): umum 120; `sign-in/email` 5; `sign-up/email` 5; `request-password-reset` 3; `reset-password` 5; `send-verification-email` 3; `change-password` 5. Origin harus ada di `TRUSTED_ORIGINS` (atau `BETTER_AUTH_URL`) untuk permintaan berbasis browser; klien mobile tanpa header `Origin`.

## 4. Identitas, consent, onboarding

| Metode | Path | Consent | Keterangan |
|---|---|---|---|
| GET · PATCH | `/api/me/profile` | — | `displayName`, `birthYear` |
| GET · PUT · PATCH | `/api/me/health-profile` | — | `PUT` penuh, `PATCH` parsial; menghitung ulang `eligibilityStatus` |
| GET · PATCH | `/api/me/preferences` | — | `locale`, `timezone`, `glucoseUnit`, `textSize`, `reduceMotion` |
| GET | `/api/me/consents` | — | status per tujuan + riwayat |
| POST | `/api/me/consents` | — | `{policyVersion, purposes[], source}` |
| POST | `/api/me/consents/withdraw` | — | `{purposes[]}` |
| GET · PATCH | `/api/me/onboarding` | — | state diturunkan; `PATCH {introSeen:true, expectedVersion?}` |
| POST | `/api/me/onboarding/complete` | — | `409 ONBOARDING_INCOMPLETE {missingSteps}` bila belum lengkap |
| GET | `/api/me/export` | — (sengaja) | ekspor data milik sendiri, 5/jam; format `beokay-export-v2` mencakup semua tabel ber-`user_id` kecuali yang tercantum di `excluded` beserta alasannya |
| POST | `/api/me/account/delete` | — | `{password, confirm: "HAPUS"}`; `403 INVALID_PASSWORD`; 5 percobaan / 15 menit; menghapus akun dan semua data (cascade), email konfirmasi dikirim. `/api/auth/delete-user` diblokir (404) |

## 5. Pencatatan

Semua baris berikut: **Consent H** (ringkasan juga **S**).

| Domain | Metode + Path |
|---|---|
| Makanan (katalog) | GET `/api/foods/search?q=` · POST `/api/me/foods` · PATCH `/api/me/foods/:id` |
| Makan | GET, POST `/api/me/meals` · GET, PATCH `/api/me/meals/:id` · GET `/api/me/meals/:id/revisions` |
| Glukosa | GET, POST `/api/me/glucose` · GET `/api/me/glucose/summary` (**S**) · GET, PATCH `/api/me/glucose/:id` · GET `…/:id/revisions` |
| Aktivitas | GET, POST `/api/me/activities` · POST `/api/me/activities/import` · GET `/api/me/activities/summary` (**S**) · GET `/api/me/activities/weekly` (**S**) · GET, PATCH `/api/me/activities/:id` · GET `…/:id/revisions` |
| Obat | GET, POST `/api/me/medications` · GET `/api/me/medications/today` · GET, PATCH `/api/me/medications/:id` · GET `…/:id/revisions` · GET, POST `…/:id/schedules` · PATCH `…/:id/schedules/:scheduleId` · GET, POST `…/:id/intakes` · GET, PATCH `…/:id/intakes/:intakeId` |
| Tujuan | GET, POST `/api/me/goals` · GET, PATCH `/api/me/goals/:id` · GET, POST `…/:id/checkins` · PATCH `…/:id/checkins/:checkinId` |
| Timeline | GET `/api/me/timeline?domain=all|meal|glucose|activity|medication|goal&date=&cursor=&limit=&archived=` |
| Preferensi makanan | GET, POST `/api/me/food-preferences` · POST `…/check` · PATCH `…/:id` |
| Pengingat | GET, POST `/api/me/reminders` · GET `…/upcoming?days=1..14` · PATCH `…/:id` |
| Sinkronisasi | POST `/api/me/sync/operations` (1–50 operasi) · GET `/api/me/sync/status` |

Catatan khusus:
- `GET /api/me/medications/today` mengembalikan kemunculan jadwal; yang belum dikonfirmasi berstatus `unknown`.
- `POST /api/me/activities/import` `{source: "health_connect"|"apple_health", sessions[1..100]}` → hasil per sesi `CREATED | CREATED_NEEDS_REVIEW | DUPLICATE | REJECTED`.
- `POST /api/me/sync/operations` → `{items:[{operationId, status: SYNCED|CONFLICT|NEEDS_REVIEW|SYNC_FAILED, recordId, result?, error?}]}`; `403 CONSENT_REQUIRED` untuk seluruh permintaan bila consent H ditarik.

## 6. Ringkasan dan insight (Consent H + S)

| Metode | Path | Parameter |
|---|---|---|
| GET | `/api/me/today` | — |
| GET | `/api/me/summaries/daily` | `date?` |
| GET | `/api/me/summaries/weekly` | `date?` |
| GET | `/api/me/insights/contextual` | — |
| GET | `/api/me/trends` | `days ∈ {7,14,30,90}` (default 14) |
| GET | `/api/me/insights/statistics` | `days ∈ {7,14,30,90}` (default 14). Statistik bermetadata (`stats-v1`), kartu insight (`insight-rules-v1`, semua kandidat hingga 5; urutan tampil ditentukan klien), dan seri harian makronutrien/aktivitas/glukosa/obat. Lihat `docs/reports/beokay-3.0-phase-0-2.md` §5 |

## 7. Pencarian makanan dan pemindaian (Consent H)

| Metode | Path | Keterangan |
|---|---|---|
| GET | `/api/me/foods/discover?q=&external=&hideExcluded=` | `q` 2–80 karakter; `external=true` mengirim kata kunci ke OFF/USDA (20/10 mnt) |
| GET | `/api/me/foods/web-search?q=` | Brave; hanya tautan + cuplikan; `NOT_CONFIGURED` tanpa kunci |
| GET | `/api/me/foods/reference?q=` | langsung ke TKPI (hibrida) |
| GET | `/api/me/foods/barcode/:code` | GTIN tervalidasi → Open Food Facts |
| GET · POST | `/api/me/foods/:id/measures` | ukuran porsi rumah tangga |
| POST | `/api/me/nutrition/calculate` | hitung gizi tanpa menyimpan; `computationVersion: portion-calc-v1` |
| POST | `/api/me/foods/scan/label` | badan = byte gambar; OCR + parser; hasil `READ | NO_NUTRITION | UNAVAILABLE` |
| POST | `/api/me/foods/scan/photo` | badan = byte gambar; `IDENTIFIED | NOT_FOOD | UNAVAILABLE` (+ `modelHint` bila model `APPROVED`) |

`UNAVAILABLE` membawa `code` (mis. `PROVIDER_NOT_CONFIGURED`) — bukan galat HTTP.

## 8. Push

| Metode | Path | Consent | Keterangan |
|---|---|---|---|
| GET · POST | `/api/me/push-devices` | H | `POST` → `201` baru / `200` ada; token tidak pernah dikembalikan utuh; maks 5 perangkat aktif |
| DELETE | `/api/me/push-devices/:id` | — | menghapus token |

## 9. Agen, personalisasi, rencana (P2)

| Metode | Path | Consent | Keterangan |
|---|---|---|---|
| POST | `/api/me/agent/runs[?async=1]` | H + A | `{idempotencyKey(8–100), message(2–2000), query?(2–80), previousRunId?}`; `201` sinkron / `202` latar; batas 20 run / 10 mnt |
| GET | `/api/me/agent/runs/:id` | (status `consentRequired`) | tampilan run + peristiwa + rekomendasi |
| GET | `/api/me/agent/runs/:id/stream` | — | SSE; `Last-Event-ID` atau `?after=`; maks 45 dtk; peristiwa akhir `state` |
| POST | `/api/me/agent/runs/:id/cancel` | — | `409 RUN_NOT_CANCELLABLE` bila sudah selesai |
| GET | `/api/me/agent/pending` | H + A (bila kurang → `consentRequired:true`, bukan 403) | run menunggu keputusan (pemulihan setelah restart) |
| POST | `/api/me/agent/recommendations/:id/decision` | H + A | `{operationId, decision: ACCEPT|REJECT, expectedVersion}` |
| POST | `/api/me/agent/recommendations/:id/feedback` | H + A | `{operationId, kind: CONSUMED|NOT_CONSUMED|COMPLETED|SKIPPED, activitySessionId?}`; hanya rekomendasi `ACCEPTED` |
| GET | `/api/me/agent/tools` | — | kontrak alat terdaftar; sejak 3.0 Fase 3 `requiredPermissions` ditegakkan di `executeTool` (tanpa consent → `PERMISSION_DENIED`, tercatat `DENIED`) |
| GET | `/api/me/planned-meals` · `/api/me/activity-plans` | H | rencana (bukan catatan) |
| GET · DELETE | `/api/me/personalization` | GET: A | ringkasan / reset profil personalisasi |
| GET | `/api/me/ml/models` | — | katalog model + status (`usableForUsers` hanya `APPROVED`) |
| POST | `/api/me/ml/warmup` | — | selalu `202 {accepted:true}` agar status tidak bocor |

### 9a. Percakapan Asisten (3.0 Fase 3)

| Metode | Path | Consent | Keterangan |
|---|---|---|---|
| GET | `/api/me/conversations` | H | 30 thread terbaru: `id`, `title`, `messageCount`, `lastMessageAt` |
| GET | `/api/me/conversations/:id` | H | thread + semua pesan; bagian `recommendations` diisi status saran terkini (`hidden:true` bila consent A dicabut); thread orang lain → `404` |
| POST | `/api/me/conversations/:id/messages` | H (+ A untuk makanan/aktivitas, + S untuk ringkasan; kekurangan dijawab sebagai bagian `consent_required`, bukan 403) | `{clientMessageId: uuid, text(1–1000), photo?: {items: [{name(2–60), confidence: high|medium|low}] (1–6)}}` — `photo` berisi nama hasil `/foods/scan/photo`, bukan gambar; thread dibuat otomatis dengan `id` dari klien; `201` baru, `200` + `replayed:true` untuk `clientMessageId` yang sama; teks berbeda → `409 IDEMPOTENCY_CONFLICT`; sedang diproses → `409 MESSAGE_IN_PROGRESS`; `422 THREAD_FULL` (400 pesan); `429 CONVERSATION_RATE_LIMITED` (30 pesan / 10 mnt) |
| DELETE | `/api/me/conversations/:id` | — | hapus thread dan pesan; saran terbuka dari thread itu menjadi `INVALIDATED`, run terkait `CANCELLED`, `input_text` run disamarkan; rencana yang sudah diterima tetap |

Balasan berupa bagian bertipe: `text`, `statistic` (dari `stats-v1`), `recommendations` (run agen), `no_match`, `safety`, `notice`, `consent_required`, `suggestions`, `link` (`INSIGHTS`/`LOG`/`LOG_MEAL`/`CONSENT`), `meal_draft` (diisi status draf terkini), `memory_proposal` (diisi status ingatan terkini); pesan pengguna dapat membawa bagian `photo`. Pesan asisten membawa `basis` `{sources: [{kind, label}], memories: [{id, content}]}` bila jawabannya memakai data atau ingatan. Rute dipilih router deterministik `router-v1` (`conversation.router.ts`).

### 9b. Draf catatan makan & memori (3.0 Fase 4)

| Metode | Path | Consent | Keterangan |
|---|---|---|---|
| GET | `/api/me/meal-drafts/:id` | H | tampilan draf: `status` (`PROPOSED`/`SAVED`/`DISCARDED`/`EXPIRED`), `items[]` dengan `candidates[]` (`TKPI`/`CATALOG`/`WEB`), `selected`, `grams` hanya bila disebut atau dari takaran milik pengguna |
| POST | `/api/me/meal-drafts/:id/confirm` | H | `{expectedVersion, category, consumedAt, items: [{index, candidateKey|null, name, quantity, unit, grams|null}]}`; `candidateKey` harus berasal dari kandidat item itu (`422 INVALID_CANDIDATE`); ID draf = ID catatan makan, jadi ulang = `200 replayed`; `409 VERSION_CONFLICT`/`DRAFT_EXPIRED`/`DRAFT_NOT_OPEN` |
| POST | `/api/me/meal-drafts/:id/items/:index/web-search` | H | pencarian web Firecrawl atas permintaan pengguna untuk satu makanan; balas `{status: FOUND|NONE|UNAVAILABLE|NOT_CONFIGURED, draft}`; sekali per item (kecuali `UNAVAILABLE`); `429 WEB_SEARCH_RATE_LIMITED` (10 / 10 mnt) |
| POST | `/api/me/meal-drafts/:id/discard` | — | buang draf terbuka |
| GET · DELETE | `/api/me/memories` | — | daftar ingatan aktif `{enabled, consentGiven, active, items}` / hapus semua |
| PATCH · DELETE | `/api/me/memories/:id` | — | ubah isi `{content(1–160), expectedVersion}` / hapus satu |
| POST | `/api/me/memories/:id/confirm` · `/dismiss` | A + ingatan aktif (confirm) | jadikan usulan aktif / tolak usulan |
| PATCH | `/api/me/memory-preferences` | — | `{enabled}`; mematikan menghapus usulan yang belum dijawab dan menghentikan pemakaian |

Alat agen baru `search_web_nutrition` (maksud `MEAL_DRAFT_ENRICHMENT`, consent H) memanggil Firecrawl `v2/search` dan hanya mengembalikan nama dari judul halaman, URL, host, dan angka per 100 g yang lolos parser deterministik. Tanpa `FIRECRAWL_API_KEY`, endpoint pencarian web membalas `NOT_CONFIGURED`.

### 9c. Rencana kecil & refleksi mingguan (3.0 Fase 5) — Consent H + A (refleksi: H + S)

| Metode | Path | Keterangan |
|---|---|---|
| GET | `/api/me/coaching` | ringkasan: `opportunities[]` (usulan `PROPOSED` yang didukung catatan), `withheld[]` (sumber yang ditahan beserta alasan: `MUTED_BY_USER`, `SNOOZED`, `PLAN_ALREADY_RUNNING`, `ALL_VARIANTS_DECLINED`, `SUGGESTION_LIMIT`, `DURATION_ABOVE_SAFE_CAP`, `ACTIVITY_DISLIKED`), `actions[]` (rencana diterima 14 hari terakhir dengan `dayStates[]` dan `phase` `RUNNING`/`ENDED`), `reflection`, `preferences`; tanpa consent → `consentRequired: true` dan usulan terbuka kedaluwarsa |
| GET | `/api/me/coaching/opportunities` | hanya usulan; menjalankan rekonsiliasi dan menghapus usulan yang tidak lagi didukung data (`NO_LONGER_SUPPORTED`) |
| POST | `/api/me/coaching/actions/:id/decision` | `{operationId, decision: ACCEPT|DECLINE|WITHDRAW, slot?, reminder?: {localTime?}}`; tepat sekali per `operationId` (ulang = `replayed`, isi berbeda = `409 OPERATION_ID_REUSED`); `409 ACTION_NOT_OPEN`/`ACTION_EXPIRED`; `ACCEPT` memulai rencana hari ini dan (opsional) membuat pengingat yang diarsipkan otomatis saat rencana selesai/dihentikan; `422 REMINDER_LIMIT` |
| POST | `/api/me/coaching/actions/:id/feedback` | `{operationId, kind, slot?}`; `kind`: `HELPFUL`, `NOT_HELPFUL` (sekali per rencana, `409 FEEDBACK_ALREADY_RECORDED`), `ALREADY_DONE`, `NOT_NOW`, `TOO_FREQUENT`, `PREFER_DIFFERENT_TIME` (`slot` wajib), `PREFER_DIFFERENT_SUGGESTION`, `STOP_THIS_TYPE`; setiap akibat tercatat di `personalization_events` |
| POST | `/api/me/coaching/actions/:id/confirm` | `{operationId, date}` → hari itu `USER_CONFIRMED` (terpisah dari `OBSERVED`); hanya hari rencana yang sudah lewat atau hari ini (`422 DATE_NOT_IN_PLAN`) |
| GET | `/api/me/coaching/checkins` | refleksi minggu sasaran (minggu berjalan bila sudah ≥ 4 hari, selain itu minggu lalu): ringkasan deskriptif, tujuan, status rencana, `positives[]`, `adjustments[]` (hanya penurunan, tujuan `weekly` non-glukosa), `streak`, `history[]`, `memoryAvailable`, `preferredSlot`, `nudge` |
| POST | `/api/me/coaching/checkins` | `{operationId, weekStart, mood?: GOOD|MIXED|HARD, hardest[]?: TIME|FORGOT|ENERGY|MOTIVATION|OTHER, note?(≤280), adjustments[]: [{goalId, toTarget}], preferredSlot?, rememberSlot?}` → `201 {checkin, recognition[]}`; penyesuaian harus sama dengan usulan (`422 ADJUSTMENT_NOT_OFFERED`), minggu harus minggu sasaran (`422 WEEK_NOT_OPEN`), satu per minggu (`409 CHECKIN_EXISTS`), ulang dengan `operationId` yang sama = `replayed` |

Status per hari rencana: `PLANNED`, `OBSERVED` (ada catatan yang cocok), `USER_CONFIRMED` (dikonfirmasi sendiri), `NOT_OBSERVED` (hari lewat tanpa catatan; bukan "gagal"), `RETRACTED` (catatan pembuktinya dihapus), `UNKNOWN` (tanpa izin membaca catatan).

## 10. Komunitas (P2) — Consent per tujuan

| Metode | Path | Consent |
|---|---|---|
| GET | `/api/regions` | — |
| GET | `/api/me/communities?regionCode=NN` | — (direktori; jumlah anggota < 5 dikaburkan) |
| GET | `/api/me/communities/mine` | tanpa `community_membership` → `{items:[], consentRequired:true}` (bukan galat) |
| POST | `/api/me/communities/:id/join` `{alias}` | `community_membership` |
| PATCH | `/api/me/communities/:id/alias` | `community_membership` |
| POST | `/api/me/communities/:id/leave` | — |
| GET | `/api/me/communities/:id/challenges` | `community_membership` |
| POST | `/api/me/challenges/:id/join` `{leaderboardVisible}` | `community_membership` + `challenge_participation` (+ `leaderboard_visibility` bila tampil) |
| POST | `/api/me/challenges/:id/leave` | — |
| PATCH | `/api/me/challenges/:id/visibility` `{visible}` | `leaderboard_visibility` bila `true` |
| POST | `/api/me/challenges/:id/checkins` `{localDate?}` | `community_membership` + `challenge_participation` |
| GET | `/api/me/challenges/:id/progress` | `challenge_participation` |
| GET | `/api/me/challenges/:id/leaderboard?limit=&offset=` | `community_membership`; `suppressed:true` bila kohort < 5 |

Kode galat khas: `INVALID_ALIAS` (422), `ALIAS_TAKEN` (409), `NOT_A_MEMBER` (403), `CHALLENGE_CLOSED` (409), `NOT_PARTICIPATING` (409), `CHECKIN_IN_FUTURE | CHECKIN_TOO_OLD | CHECKIN_OUTSIDE_WINDOW` (422).

## 11. Intervensi (P3 awal) — Consent H + A

| Metode | Path | Keterangan |
|---|---|---|
| POST | `/api/me/interventions/evaluate` | `{trigger: USER_REQUESTS_SUPPORT|GOAL_WINDOW_APPROACHING|USER_SELECTED_ROUTINE_REMINDER|WEEKLY_REVIEW_AVAILABLE|COACHING_ACTION_DUE, goalId?}`; selalu mencatat keputusan; sejak `jitai-policy-v2` balasan memuat `decision`: `INTERVENE`, `DO_NOT_INTERVENE`, `DEFER` (jam tenang, jatah, terlalu cepat, ditunda, `SLOT_NOT_STARTED`), `ASK_FOR_CLARIFICATION` (opsi `CLARIFICATION_QUESTION` setelah tanggapan `NOT_USEFUL` terakhir), `REQUIRES_REVIEW` (rencana gagal validasi ulang keselamatan) |
| GET | `/api/me/interventions` | kartu terbuka (maks 5) |
| POST | `/api/me/interventions/:id/response` | `{kind, snoozeMinutes?}`; `409 CONSENT_REQUIRED` *(bukan 403 — audit F-14)* |
| GET · PATCH | `/api/me/intervention-preferences` | jeda, jam tenang, jatah, `mutedTriggers` |

## 12. Cakupan koleksi Bruno

`docs/api/bruno/` berisi koleksi untuk modul 08–19 (Today, Nutrition, Glucose, Activity, Medication, Goals, Sync & weekly, Food discovery & calculator, Trends, Security/negative, Food preferences & reminders, Reference/export/import/insights) dan satu environment `test`. **Belum ada** koleksi untuk `foods/scan/*`, push, agen, komunitas, ML, dan intervensi; cakupan endpoint tersebut hanya dari tes integrasi Bun. Menurut catatan proyek, koleksi 18–19 belum pernah dijalankan lewat CLI.
