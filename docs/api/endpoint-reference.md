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

### 8a. Notifikasi & realtime (3.0 Fase 6)

| Metode | Path | Keterangan |
|---|---|---|
| GET | `/api/me/notifications?cursor=&limit=` | kotak masuk terbaru dulu; `limit` 1–50 (default 20); `{items[], nextCursor, unread}`; item: `id, kind, title, body, action, refId, read, createdAt` |
| GET | `/api/me/notifications/unread-count` | `{unread}` |
| POST | `/api/me/notifications/:id/read` | `{id, read: true, unread}`; milik pengguna lain → `404` |
| POST | `/api/me/notifications/read-all` | `{updated, unread: 0}` |
| GET · PATCH | `/api/me/notification-preferences` | `{pushEnabled?, mutedKinds?[]}` (minimal satu); balasan juga memuat `kinds[]`, `pushConfigured` (server punya kredensial FCM), `devices` (perangkat push aktif) |
| GET (upgrade) | `/api/me/realtime` | WebSocket; sesi dari header `Authorization: Bearer` atau cookie; tanpa sesi terverifikasi → `401`, bukan permintaan upgrade → `426 UPGRADE_REQUIRED` |

`kind`: `REMINDER`, `COACHING`, `REFLECTION`, `CHALLENGE`, `RECOGNITION`. `action`: `OPEN_HOME`, `OPEN_LOG`, `OPEN_COACHING`, `OPEN_REFLECTION`, `OPEN_CHALLENGE`, `OPEN_COMMUNITY`, `OPEN_RECOGNITIONS`, `OPEN_REMINDERS`, `OPEN_GOALS`, `OPEN_MEDICATIONS`. Jenis yang dibisukan tidak dibuat sama sekali. Setiap notifikasi punya `dedupe_key` unik per pengguna, jadi pekerja yang berjalan ulang tidak menggandakannya. Push FCM hanya membawa teks layar kunci yang umum ("Pengingat beOkay — Buka beOkay untuk mencatat.") dan data `{action, refId}`; judul dan isi aslinya hanya ada di kotak masuk.

**Protokol WebSocket** (JSON per pesan, maks 4 KB, idle 120 dtk):

| Arah | Pesan |
|---|---|
| server → klien | `hello {unread}` saat terhubung; `notification {item, unread}`; `notifications.read {ids? \| all, unread}`; `coaching.updated {actionId? \| checkinId?}`; `challenge.progress {challengeId, score, activeDays}`; `leaderboard.changed {challengeId}` (hanya ke topik tantangan); `pong {at}`; `subscribed`/`unsubscribed {topic}`; `error {code}` (`BAD_MESSAGE`, `TOPIC_FORBIDDEN`, `UNKNOWN_MESSAGE`) |
| klien → server | `ping`; `subscribe {topic}`; `unsubscribe {topic}` |

Setiap koneksi otomatis berlangganan `user:<id>`. Topik lain hanya `challenge:<uuid>` dan hanya untuk anggota aktif komunitas tantangan itu (maks 20 topik). Sesi diperiksa ulang paling lama tiap 60 dtk saat ada pesan; sesi yang dicabut/kedaluwarsa ditutup dengan kode `4401 SESSION_ENDED`. Klien Flutter mengirim `ping` tiap 25 dtk dan menyambung ulang dengan jeda bertahap.

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
| GET | `/api/me/coaching/checkins` | refleksi minggu sasaran (minggu berjalan bila sudah ≥ 4 hari, selain itu minggu lalu): ringkasan deskriptif, tujuan, status rencana, `positives[]`, `adjustments[]` (sejak Fase 8 `coach-rules-v2` dua arah: `direction: DOWN` bila < 60% target, `UP` bila tercapai ≥ 2 dari ≤ 4 minggu terakhir, ke persentil ke-60 dibatasi +10% atau +1 untuk tujuan hitungan; tujuan `weekly` non-glukosa), `strategies` (`strategy-catalog-v1`, `byBarrier`, `reviewStatus`), `previousStrategy`, `streak`, `history[]`, `memoryAvailable`, `preferredSlot`, `nudge` |
| POST | `/api/me/coaching/checkins` | `{operationId, weekStart, mood?: GOOD|MIXED|HARD, hardest[]?: TIME|FORGOT|ENERGY|MOTIVATION|OTHER, note?(≤280), adjustments[]: [{goalId, toTarget}], preferredSlot?, rememberSlot?, strategy?: {barrier, key}}` → `201 {checkin, recognition[]}`; penyesuaian harus sama dengan usulan (`422 ADJUSTMENT_NOT_OFFERED`), strategi harus untuk hambatan yang dipilih (`400`) dan ada di katalog (`422 STRATEGY_NOT_OFFERED`) lalu menjadi rencana `PROBLEM_SOLVING`/`HABIT_STEP` 7 hari, minggu harus minggu sasaran (`422 WEEK_NOT_OPEN`), satu per minggu (`409 CHECKIN_EXISTS`), ulang dengan `operationId` yang sama = `replayed` |

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
| GET | `/api/me/challenges/:id` *(Fase 6)* | `community_membership` + anggota aktif; detail: `status`, `statusLabel`, `daysLeft`, `participantsLabel`, `rules[]`, `progress`, `myResult`, `canJoin`, `canCheckin`, `checkedInToday`, `alias` |
| GET | `/api/me/challenges/history` *(Fase 6)* | tantangan `CLOSED` yang pernah diikuti beserta `myResult` (`COMPLETED`/`PARTICIPATED`/`LEFT`, `finalActiveDays`, `finalScore`) |
| GET | `/api/me/community/overview` *(Fase 6)* | ringkasan hub: `memberships`, `challenges` berjalan/terjadwal + progres, `recognitions` (maks 6), `upcomingRecognitions` (maks 3), `highlight` untuk Beranda (`CHALLENGE` atau `RECOGNITION` ≤ 7 hari; `null` bila dimatikan), `highlightsEnabled`; tanpa `community_membership` → `consentRequired: true` dengan pengakuan pribadi saja |
| GET · PATCH | `/api/me/community/privacy` *(Fase 6)* | apa yang dibagikan dan tidak pernah dibagikan, alias per komunitas, papan peringkat tempat alias tampil; `PATCH {highlightsEnabled}` |
| POST | `/api/me/community/privacy/hide-leaderboards` *(Fase 6)* | menyembunyikan alias dari semua papan peringkat sekaligus (diaudit `leaderboards_hidden`) |
| GET | `/api/me/recognitions` *(Fase 6)* | pengakuan usaha pribadi `recognition-v1`: `items[]` (tercapai), `upcoming[]` (belum), `note`; tidak pernah tampil ke anggota lain |

Sejak Fase 6, `GET /api/me/communities/:id/challenges` dan daftar `communities` memuat `status` (`SCHEDULED`/`OPEN`/`CLOSED`), `statusLabel` ("Mulai besok", "Berjalan · sisa 5 hari", "Selesai"), `daysLeft`, dan `participantsLabel` ("kurang dari 5 peserta" bila < 5). Tantangan dibuat dan ditutup otomatis oleh siklus `challenge-lifecycle-v1` (lihat `server-modules.md`).

Kode galat khas: `INVALID_ALIAS` (422), `ALIAS_TAKEN` (409), `NOT_A_MEMBER` (403), `CHALLENGE_NOT_FOUND` (404), `CHALLENGE_CLOSED` (409), `NOT_PARTICIPATING` (409), `CHECKIN_IN_FUTURE | CHECKIN_TOO_OLD | CHECKIN_OUTSIDE_WINDOW` (422).

## 11. Intervensi (P3 awal) — Consent H + A

| Metode | Path | Keterangan |
|---|---|---|
| POST | `/api/me/interventions/evaluate` | `{trigger: USER_REQUESTS_SUPPORT|GOAL_WINDOW_APPROACHING|USER_SELECTED_ROUTINE_REMINDER|WEEKLY_REVIEW_AVAILABLE|COACHING_ACTION_DUE, goalId?}`; selalu mencatat keputusan; sejak `jitai-policy-v2` balasan memuat `decision`: `INTERVENE`, `DO_NOT_INTERVENE`, `DEFER` (jam tenang, jatah, terlalu cepat, ditunda, `SLOT_NOT_STARTED`), `ASK_FOR_CLARIFICATION` (opsi `CLARIFICATION_QUESTION` setelah tanggapan `NOT_USEFUL` terakhir), `REQUIRES_REVIEW` (rencana gagal validasi ulang keselamatan) |
| GET | `/api/me/interventions` | kartu terbuka (maks 5) |
| POST | `/api/me/interventions/:id/response` | `{kind, snoozeMinutes?}`; `403 CONSENT_REQUIRED` (sejak 3.0 Fase 7, audit F-14) |
| GET · PATCH | `/api/me/intervention-preferences` | jeda, jam tenang, jatah, `mutedTriggers` |

## 11a. Fase 8 — ukur dan ringankan

| Metode | Path | Consent | Keterangan |
|---|---|---|---|
| GET · POST · DELETE | `/api/me/usage-events` | `product_analytics` (tanpa consent POST membalas `202 {accepted: 0, recorded: false}`) | POST `{appVersion?, platform?, events[≤50]: {type: screen_opened|notification_opened|quick_repeat_used|context_viewed|form_saved|suggestion_offered, domain?, meta: {via?, screen?, durationMs?, source?, trigger?, kind?, position?, shown?}, occurredAt}}`; kunci lain atau teks bebas → `400`; peristiwa > 7 hari atau > 10 menit di depan dibuang; 30 batch/menit (`429 USAGE_RATE_LIMITED`). GET: jumlah per jenis. DELETE: hapus semua. Peristiwa `record_created`, `suggestion_*`, `reflection_completed`, `strategy_chosen` dicatat server dalam transaksi yang sama dengan catatannya |
| GET | `/api/me/features` | — | `{features: {assistant, conversation, coaching, community, ml_inference, food_vision, web_discovery, analytics, push}, labels}`; rute fitur yang mati → `503 FEATURE_DISABLED` `{details: {feature}}` |
| GET · POST | `/api/me/vitals` | H | `kind=`, `cursor`, `limit`, `archived`; POST `{id, kind, value, value2?, unit, measuredAt, notes?}` idempoten; `422 UNIT_NOT_ALLOWED|VALUE_OUT_OF_RANGE|SYSTOLIC_NOT_ABOVE_DIASTOLIC|SECOND_VALUE_NOT_ALLOWED` |
| GET · PATCH | `/api/me/vitals/:id` | H | koreksi `{expectedVersion, reason, value?, value2?, unit?, measuredAt?, notes?, archived?}` → revisi |
| GET | `/api/me/vitals/:id/revisions` | H | |
| GET · POST | `/api/me/labs` | H | `test=`; POST `{id, test, value, unit, sampledAt (YYYY-MM-DD), labName?, source: manual|lab_report, notes?}` |
| GET · PATCH | `/api/me/labs/:id`, GET `/api/me/labs/:id/revisions` | H | sama dengan vital |
| GET | `/api/me/clinical/summary` | H + S | terbaru + sebelumnya per jenis, `change {difference, direction}` deskriptif, `hba1c {status: NONE|RECENT|DUE, lastSampledAt, dueOn, daysSince}` (90 hari); tanpa label klinis |
| GET | `/api/me/quick-record/suggestions` | H | ≤ 5 makan (dikelompokkan menurut isi yang sama) dan ≤ 5 aktivitas manual (jenis, durasi, intensitas) dari 30 hari, urut frekuensi lalu terbaru; `template` siap dikirim ke `POST /api/me/meals` / `/api/me/activities` dengan `id` dan waktu baru |
| GET | `/api/me/glucose/:id/context` | H + S | median pribadi 14 hari dengan konteks sama (atau semua konteks bila `unknown`/`other`), minimal 3 catatan; `line` netral; `previous`; `alert` |
| GET | `/api/me/meals/:id/context` | H + S | karbohidrat vs median kategori yang sama (hanya bila lengkap); `glucosePair {before (−90…+10 menit), after (+60…+180 menit, terdekat ke +120), difference, note}` |
| GET · POST | `/api/me/reports` | — | POST `{category: bug|adverse_event|privacy|other, message (5–2000), contactOk, appVersion?}` → `201 {id, emailed, message}`; 5/jam (`429 REPORT_RATE_LIMITED`); GET: 20 laporan terakhir milik sendiri |

Sejak Fase 8 setiap catatan glukosa memuat `alert` (`null` atau `{level: LOW|HIGH, title, message, policyVersion, thresholdMgDl}`) dengan ambang `GLUCOSE_LIMITS` yang sama dengan keselamatan Asisten (< 70, ≥ 300 mg/dL). Domain sinkron luring bertambah `vital` dan `lab`. Notifikasi jenis `LAB_REMINDER` (aksi `OPEN_CLINICAL`) dibuat sekali per hasil HbA1c yang sudah ≥ 90 hari.

## 11b. Fase 9 — sinyal perangkat dan operasi

| Metode | Path | Consent | Keterangan |
|---|---|---|---|
| GET · PATCH | `/api/me/device-import/preferences` | H (PATCH) | `{workouts, steps, weight, glucose, sleep}`, semua `false` secara bawaan; PATCH sebagian, diaudit `device_import_preferences_updated` |
| POST | `/api/me/device-import` | H | `{source: "health_connect", steps[≤62]: {localDate, steps}, weights[≤100]: {externalId, measuredAt, kg}, glucose[≤300]: {externalId, measuredAt, value, unit, specimen?, mealContext?}, sleep[≤62]: {externalId, startedAt, endedAt}}`; jenis yang dimatikan → `REJECTED/DEVICE_TYPE_DISABLED`; langkah per tanggal lokal diganti nilai terbaru (`upserted`/`unchanged`), tanggal di depan hari ini ditolak; berat → `vital_measurements` `source=health_connect`; glukosa → `glucose_observations` `source=health_connect`, `quality_status=device_reported` (dihitung di ringkasan, statistik, tren, konteks); semua idempoten per `(user, source, externalId)` |
| GET | `/api/me/steps?days=7|14|30|90` | H | deret harian (`null` = tidak ada data), `daysWithData`, `medianSteps`, `latest` |
| GET | `/api/me/sleep?days=` | H | sesi tidur + median durasi, tanpa penilaian kualitas |
| GET | `/api/me/medications/upcoming?days=1..3` | H | kejadian obat yang belum dikonfirmasi dan belum lewat; teks layar kunci umum (tanpa nama obat) untuk notifikasi lokal dengan aksi "Sudah" |
| GET | `/api/me/report-summary?days=14|30|90` | H + S | `report-summary-v1`: statistik `stats-v1` (tanpa gizi kecuali karbohidrat), langkah, ukuran tubuh dan lab terakhir, obat aktif, `disclaimer`; sumber PDF di aplikasi dan halaman baca-saja |
| GET · POST | `/api/me/share-links` | H + S | POST `{periodDays: 14|30|90, hours: 1..168, label?, confirm: true}` → `201 {id, url, expiresAt, notice}`; maksimal 5 aktif (`422 SHARE_LINK_LIMIT`); hanya hash SHA-256 token yang disimpan |
| POST | `/api/me/share-links/:id/revoke` | — | cabut; tautan langsung `410` |
| GET | `/s/:token` | publik | HTML baca-saja (`noindex`, CSP tanpa skrip, `no-store`); `404` token tidak dikenal, `410` dicabut/kedaluwarsa/consent pemilik ditarik; tiap akses menambah `accessCount` dan diaudit `share_link_viewed`; 30 akses/menit per IP |
| GET | `/metrics` | `METRICS_TOKEN` (Bearer); tanpa token hanya di luar `production` | format Prometheus: `beokay_http_requests_total{method,route,status}`, histogram `beokay_http_request_duration_ms`, `beokay_log_events_total{level,event}`, `beokay_outbox_events{status}`, `beokay_push_deliveries_24h{status}`, `beokay_notifications_unread`, `beokay_incident_reports_unemailed`, `beokay_feature_enabled{feature}`, `beokay_database_up`, uptime, memori; rute dinormalisasi tanpa ID |

Tujuan baru `goalType: daily_steps` (metode `SUM_DEVICE_STEPS`). Refleksi mingguan menawarkan penyesuaian tujuan langkah harian dari persentil ke-60 10 hari terakhir (naik/turun paling banyak 10%).

Sejak Fase 9 semua balasan membawa `Content-Security-Policy` (API: `default-src 'none'`), `Cross-Origin-Resource-Policy: same-origin`, `Permissions-Policy`, dan di `production` `Strict-Transport-Security`.

## 11c. Fase 10 — hibrida agentik v2

- **Tujuan consent baru** `ai_message_understanding` (opsional). Tanpa consent ini, pesan yang tidak dikenali aturan tetap dijawab "belum paham" dengan pilihan tetap.
- **`POST /api/me/conversations/:id/messages`**: bila router aturan (`router-v4`, sama dengan v3) menghasilkan `UNKNOWN` dan bukan nama makanan, serta consent + sakelar `llm_router` aktif, pesan dikirim ke pengklasifikasi (`intent-classifier-v1`) dan judge (`safety-judge-v1`) secara paralel. Judge `HOLD` → kartu keselamatan (`MEDICATION_ADVICE`, `URGENT_SYMPTOM`, `SELF_HARM`) atau "belum paham" (`INJECTION`). Usulan yang lolos validasi dijalankan lewat jalur deterministik yang sama dengan aturan; `routerVersion` pesan asisten menjadi `router-v4-hybrid` dan `basis.sources` memuat `{kind: "LANGUAGE_MODEL"}`. Setiap usulan tercatat di `router_proposals`.
- **Memori** (`GET /api/me/memories`, bagian `memory_proposal`): jenis baru `FOOD_CONTEXT` (kedaluwarsa 180 hari), `BARRIER` (60 hari), `HEALTH_EVENT` (7 hari; puasa 14, Ramadan 30); `expiresAt` di setiap item; ingatan yang sudah lewat tidak dipakai dan tidak ditampilkan. Kondisi "sedang kurang sehat" membatasi rencana aktivitas ≤ 10 menit dan menahan usulan aktivitas rencana kecil (`TEMPORARY_CONDITION`).
- **`GET /api/me/coaching/checkins`**: tambahan `learned {weekStart, lines[], avoidSlots[], version: "episode-v1"}` dan `memoryBarriers[]`. Waktu yang ditolak ≥ 2 kali dalam seminggu tidak lagi dipakai sebagai waktu usulan.
- **"Mengapa"** pada rencana aktivitas (`FOLLOW_UP_WHY`) memakai statistik pengguna (`why-stats-v1`): hari aktif 7 hari, sesi terpanjang dan terpendek 28 hari.
- **Sakelar fitur** baru `llm_router`.

## 11d. Fase 11 — ekosistem

- **Edukasi** (tanpa consent khusus, butuh sesi): `GET /api/education/modules` → `{version: "education-v1", items[{key, version, title, summary, topics[], readMinutes, reviewStatus, reviewedAt}], includesDrafts}`; `GET /api/education/modules/:key` → item + `sections[{heading, paragraphs[], bullets[]}]`, `authoredOn`, `reviewedBy`, `notice`. Hanya versi `REVIEWED` yang tampil kecuali `EDUCATION_INCLUDE_DRAFTS=true` (dev/uji). Kunci tidak valid → 400, tidak ada → 404.
- **Asisten**: balasan `SAFETY` (kecuali `SELF_HARM`) kini memuat bagian `{type: "education", items[{key, title, readMinutes, reviewStatus}]}` bila ada modul yang boleh tampil untuk kode itu.
- **Hidangan terkurasi**: `GET /api/me/foods/reference?q=` kini juga mengembalikan baris `status = curated`, dengan `verification: "curated"`, `provenance: "Kurasi beOkay · dari bahan TKPI"`, `source`, `sourceVersion: "curated-dishes-v1"`, `serving {minGrams, typicalGrams, maxGrams}`, dan `note` berisi metode hitung.
- **Pendamping** (consent `companion_sharing` + `health_data_processing`, sakelar `companion`): `GET/POST /api/me/companions` (`{label 1–40, days 30|90|180, confirm: true}` → 201 dengan `url` sekali tampil; maks. 3 aktif → 422 `COMPANION_LIMIT`), `POST /api/me/companions/:id/revoke`. Halaman publik `GET /c/:token` (HTML, CSP ber-nonce, `noindex`, 30 permintaan/menit/IP): hari dengan catatan, menit aktivitas, jumlah pemeriksaan glukosa, obat dikonfirmasi dari terjadwal, jam pengingat obat yang belum dikonfirmasi. Tanpa nama, nama obat, nama makanan, atau angka glukosa. 404 token salah, 410 kedaluwarsa/dicabut; penarikan consent mencabut semua tautan saat tautan berikutnya dibuka.
- **CGM** (consent `health_data_processing`, sakelar `cgm`): `POST /api/me/cgm/imports?fileName=&dateOrder=auto|MDY|DMY` dengan badan `text/csv` (maks. 4 MB, 10 impor/jam) → 201 `{rowsTotal, rowsAccepted, rowsDuplicate, rowsSkipped, periodStart, periodEnd, unit, device, dateOrder}`; 415 bukan CSV; 422 `CGM_FORMAT_UNKNOWN`, `CGM_DATE_ORDER_AMBIGUOUS`, `CGM_EMPTY`, `CGM_TOO_MANY_ROWS`. `GET /api/me/cgm/imports`, `DELETE /api/me/cgm/imports/:id` (bacaan ikut terhapus). `GET /api/me/cgm/summary?days=14|30|90` → `{bands{veryLow,low,inRange,high,veryHigh} (%), meanMgDl, meanMmolL, cvPct, coveragePct, sufficient (≥ 70%), kindUsed, limitations[], notice}`. Tidak ada saran dosis.
- **Komunitas**: `POST /api/me/challenges/:id/reports` `{alias, reason: ABUSIVE|IMPERSONATION|SPAM|OTHER}` (anggota saja; 10/hari) → 201 `{reported, duplicate, message}`; 403 bukan anggota, 404 alias tidak ada, 422 alias sendiri. Alias disembunyikan dari papan peringkat setelah 3 pelapor unik; mengganti alias memulihkan dan menutup laporan (`ALIAS_CHANGED`). `GET /api/me/communities/mine` menambah `aliasHidden`. Semua aksi komunitas dibatasi 30 per 10 menit per akun (`429 COMMUNITY_RATE_LIMITED`).
- **Ekspor FHIR R4**: `GET /api/me/export/fhir` → `application/fhir+json`, `Bundle` `collection` berisi `Patient` dan `Observation` (glukosa kapiler LOINC 41653-7, lab, berat/tinggi, tekanan darah 85354-9 dengan komponen 8480-6/8462-4, langkah 41950-7). Batas 5/jam. Lihat [../integration/satusehat-readiness.md](../integration/satusehat-readiness.md).
- **Pemakaian**: jenis peristiwa klien baru `education_opened`, `voice_input_used`, `guest_records_migrated`; domain `education`; `meta.via` `voice`/`guest`; `meta.count`.
- **Ekspor JSON**: format `beokay-export-v4` menambah `companionLinks`, `cgmImports` (dengan bacaan), `communityReports` (laporan yang dibuat pengguna sendiri).
- **Sakelar fitur** baru `companion`, `cgm`.

## 11e. Operasi serverless

- `GET|POST /internal/jobs/tick[?only=nama,nama]` dengan `Authorization: Bearer <CRON_SECRET>` (atau `x-cron-secret`) → `{version: "jobs-v1", at, jobs[{name, ran, status, result, ms}]}`. Job: `outbox_drain`, `reminder_inbox`, `push_dispatch` (tiap ≥ 1 menit), `outcome_sweep`, `challenge_lifecycle`, `coaching_nudges` (tiap jam), `education_sync` (6 jam), `retention` (23 jam). Tanpa `CRON_SECRET` atau secret salah → 404.
- `GET /internal/jobs/status` (secret sama) → waktu mulai/selesai dan status terakhir per job.

## 12. Cakupan koleksi Bruno

`docs/api/bruno/` berisi koleksi untuk modul 08–19 (Today, Nutrition, Glucose, Activity, Medication, Goals, Sync & weekly, Food discovery & calculator, Trends, Security/negative, Food preferences & reminders, Reference/export/import/insights) dan satu environment `test`. **Belum ada** koleksi untuk `foods/scan/*`, push, agen, komunitas, ML, dan intervensi; cakupan endpoint tersebut hanya dari tes integrasi Bun. Menurut catatan proyek, koleksi 18–19 belum pernah dijalankan lewat CLI.
