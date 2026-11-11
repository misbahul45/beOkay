# Referensi Modul Server

> Dibuat dari audit kode 10 November 2026. Lokasi: `server/src/features/<modul>/`. Pola berkas: `*.routes.ts` (HTTP), `*.service.ts` (aturan + transaksi), `*.repository.ts` (query), `*.schema.ts` (Zod), `*.model.ts` (fungsi murni). Konsep umum (idempotensi, versi, consent, outbox) dijelaskan di [system-overview.md](../architecture/system-overview.md) §6.
> Konvensi kolom **Consent**: `H` = `health_data_processing`, `S` = `descriptive_summaries`, `A` = `personalized_ai`. Daftar rute lengkap: [endpoint-reference.md](../api/endpoint-reference.md).

## Peta cepat

| Modul | Tabel utama | Consent | Tes unit | Tes integrasi |
|---|---|---|---|---|
| auth | `users`, `sessions`, `accounts`, `verifications` | — | — | `identity` |
| consent | `consent_records` | — | — | `identity` |
| onboarding | `onboarding_progress` | — | — | `identity` |
| profile | `user_profiles` (+ `users.name`) | — | — | `identity` |
| health-profile | `health_profiles` | — | — | `identity` |
| preferences | `user_settings` | — | — | `identity` |
| nutrition | `food_catalog`, `meal_logs`, `meal_items`, `food_portion_measures` | H, S | `nutrition` | `nutrition`, `food-calc` |
| glucose | `glucose_observations` | H, S | `glucose` | `glucose` |
| activity | `activity_sessions` | H, S | `activity` | `activity`, `activity-import` |
| medication | `medication_regimens/schedules/intakes` | H | `medication` | `medication-goals` |
| goals | `behavior_goals`, `goal_checkins` | H | `goals` | `medication-goals` |
| timeline | (query lintas tabel) | H | — | — |
| today | (komposisi) | H, S | `today` | `summaries` |
| insights | `summary_projections` | H, S | `daily`, `weekly`, `trends`, `contextual`, `statistics` | `summaries`, `trends`, `statistics` |
| sync | `sync_operations` | H | — | `sync` |
| food-discovery | — (egress ke OFF/USDA/Brave) | H | `food-discovery*`, `web-search` | — |
| food-reference | `food_reference` | H | `food-reference`, `tkpi-parser` | `food-reference` |
| food-vision | — (egress ke Mistral) | H | `food-vision-service`, `label-parser` | `food-vision` |
| food-preferences | `food_preferences` | H | `food-preferences` | `food-preferences` |
| reminders | `reminders` | H | `reminders` | `reminders` |
| push | `push_devices`, `push_deliveries` | H | `fcm` | `push` |
| export | (baca semua milik sendiri) | tidak ada | — | `export` |
| agent | `agent_runs/events/tool_calls`, `recommendations`, `recommendation_*`, `planned_meals`, `activity_plans`, `personalization_*`, `recommendation_outcomes` | H + A | `agent-safety`, `activity-graph`, `llm-text` | `agent`, `agent-activity`, `p2-closed-loop` |
| conversation | `conversation_threads`, `conversation_messages` | H (+ A/S per rute) | `conversation` | `conversation` |
| community | `regions`, `communities`, `community_memberships`, `challenges`, `challenge_*`, `score_events`, `recognitions` | tujuan komunitas | `scoring`, `community-lifecycle` | `community`, `lifecycle-realtime` |
| notifications | `notifications`, `notification_preferences` | — (isi berasal dari modul ber-consent) | — | `lifecycle-realtime` |
| ml | `model_versions`, `ml_inference_runs` | `model_inference` | `modal-client` | `ml` |
| interventions | `intervention_decisions`, `intervention_preferences` | H + A | `intervention-policy` | `interventions` |

## Identitas dan profil

### auth
`auth.ts` mengonfigurasi Better Auth; `auth.routes.ts` mem-proxy `/api/auth/*`, menimpa header IP klien, dan menyajikan dua halaman HTML kecil: `/auth/verified` dan `/auth/reset-password` (formulir reset). `guard.ts` menyediakan `authenticated()`.
Perilaku: verifikasi email wajib sebelum masuk; sesi 7 hari; token Bearer dikirim lewat header respons `set-auth-token`; email dikirim *fire-and-forget* (galat dicatat, tidak menggagalkan permintaan). Model auth bernama `Users/Sessions/Accounts/Verifications` karena adapter mencari delegate sesuai `modelName`. Perubahan konfigurasi auth memerlukan regenerasi skema — **namun skrip `auth:generate` menunjuk `src/lib/auth.ts` yang tidak ada** (lihat audit F-08).

### consent
`consent.policy.ts` adalah sumber tunggal kebijakan (versi `1.0`). `GET /api/consent-policies/current` publik. `POST /api/me/consents` (`{policyVersion, purposes[], source}`) menolak versi tidak cocok (`422 POLICY_VERSION_MISMATCH`), menutup consent versi lama (`consent_superseded`) dan membuat yang baru dalam satu transaksi. `POST /api/me/consents/withdraw`. `GET /api/me/consents` mengembalikan status per tujuan (`granted | withdrawn | not_given | reconsent_required`) plus riwayat.

### onboarding
State diturunkan oleh `deriveState()` dari: email terverifikasi, `introSeen`, dan empat langkah (consent wajib terpenuhi, profil pribadi, profil kesehatan, preferensi). `PATCH` hanya menerima `{introSeen: true, expectedVersion?}`; `POST /complete` menolak bila ada langkah tertinggal.

### profile · health-profile · preferences
- **profile**: `displayName` disimpan di `users.name` (satu sumber, diubah lewat `auth.api.updateUser`); `birthYear` di `user_profiles` (rentang `tahun−120 … tahun`).
- **health-profile**: `diagnosisStatus ∈ {diagnosed, not_diagnosed, unknown, undisclosed}`, `diabetesType ∈ {type_2, type_1, other, unknown}`, `treatmentContext[]` (`none`/`undisclosed` harus berdiri sendiri). `eligibilityStatus` dihitung ulang dari diagnosis + tahun lahir (lihat eligibility di overview). Data selalu `user_reported`.
- **preferences**: `locale` (hanya `id-ID` di API), `timezone` (divalidasi IANA via `Intl`), `glucoseUnit`, `textSize ∈ {system, large, extra_large}`, `reduceMotion`. Default dibuat saat pertama dibaca.

## Pencatatan (domain P0)

Semua rute di bawah memakai pola: `POST` (UUID klien, idempoten), `GET` daftar kursor (`cursor`, `limit` 1–50 default 20, `archived`, `date`), `GET :id`, `PATCH :id` (`expectedVersion` + `reason`), `GET :id/revisions`.

### nutrition
- `meal_logs` (kategori, `consumed_at`, `capture_method`, versi) dengan `meal_items`. Setiap item **menyalin snapshot gizi per 100 g** dari katalog saat dicatat (`source`, `sourceVersion`, `status`, lima zat gizi), sehingga perubahan katalog tidak mengubah catatan lama.
- Gizi item = `per100g × gram / 100` (Decimal, 4 desimal); `gram` = jumlah bila satuan `g` (`gramsBasis=weighed`), selain itu diisi pengguna (`user_estimate`) atau `null`.
- Total makan: per zat `{value, knownItems, totalItems, coverage}`; zat tanpa nilai tidak dihitung sebagai 0.
- Katalog: `POST/PATCH /api/me/foods` (milik sendiri), `GET /api/foods/search?q=` (milik sendiri + bersama, maks 20). `PATCH` makanan **tidak** mengubah catatan lama.

### glucose
Hanya `source=manual_glucometer`, `measurementType=capillary_blood`. `mealContext ∈ {fasting, before_meal, after_meal, bedtime, other, unknown}`; `qualityStatus ∈ {user_reported, needs_review}` (`needs_review` menambah flag `user_flagged` dan **tidak** ikut statistik). Ringkasan harian: bila < 2 pembacaan layak → `analyticsState=INSUFFICIENT_DATA`, tanpa rata-rata/min/maks. Tidak ada penilaian "tinggi/rendah".

### activity
`activityType ∈ {walking, cycling, running, strength, other}`, durasi 1–1440 menit, akhir sesi = mulai + durasi (tidak boleh melewati masa kini +5 menit). `qualityStatus`: `user_reported`, `device_reported`, `needs_review`; hanya dua pertama dihitung (`ACTIVITY_COUNTED_QUALITY`). Total jarak/langkah memakai cakupan `UNKNOWN/PARTIAL/COMPLETE`. Minggu mengikuti `Intl.Locale.getWeekInfo().firstDay`.
**Impor perangkat** (`POST /api/me/activities/import`, sumber `health_connect|apple_health`, maks 100 sesi): idempoten per `(user, source, externalId)`; sesi yang bertabrakan waktu dengan catatan lain → `CREATED_NEEDS_REVIEW` (tidak dihitung) agar tidak terhitung ganda; metrik tidak dikarang.

### medication
`medication_regimens` (nama, kekuatan, bentuk, instruksi, status `active|paused|inactive`), `medication_schedules` (jam lokal `HH:MM`, zona IANA, hari ISO 1–7), `medication_intakes` (`taken|skipped|unknown`, `medication_snapshot` JSONB). Prinsip: **jadwal bukan bukti minum**. `GET /api/me/medications/today` membentuk kemunculan jadwal hari itu; yang belum dikonfirmasi tetap `unknown` (tidak dianggap diminum atau terlewat). Indeks unik parsial `medication_intakes_occurrence_key (schedule_id, scheduled_at)` mencegah konfirmasi ganda untuk satu kemunculan. Tidak ada saran dosis.

### goals
`goalType ∈ {manual_checkins, activity_minutes, record_meals, record_glucose, walking_sessions}`, `period ∈ {daily, weekly}`, status `active|paused|completed|archived`. Check-in `completed|skipped|unknown`. Kemajuan dihitung dari catatan nyata atau check-in; tidak ada tujuan yang menghargai nilai glukosa/kalori rendah.

### timeline
Satu kueri SQL `UNION ALL` atas meal, glucose, activity, medication intake, goal check-in; kursor `base64url({at, domain, id})`. Catatan: item aktivitas selalu berlabel `source: "manual"` (audit F-09).

### today
Komposisi `nutrition.daily + glucose.daily + activity.daily + 5 item timeline` untuk tanggal lokal pengguna (`computationVersion=today-activity-v1`).

## Ringkasan dan insight

- **daily** (`daily-cross-domain-v1`): cakupan harian 0/1–2/3 domain → `UNKNOWN/PARTIAL/COMPLETE`; di-upsert ke `summary_projections` (cache).
- **weekly** (`summarizeWeek`): deskriptif; tidak ada korelasi, rata-rata glukosa, atau "kepatuhan obat"; hari tanpa catatan = tidak tercatat, bukan nol.
- **trends** (`trends-v1`): `days ∈ {7, 14, 30, 90}` (default 14) + periode pembanding sama panjang; hanya data `user_reported`/layak.
- **statistics** (`stats-v1`, `insight-rules-v1`; Fase 2 beOkay 3.0): `statistics.model.ts` murni + `statistics.service.ts`. Setiap statistik membawa nilai, satuan, rentang, sumber, jumlah sampel + minimum, cakupan, cara hitung, pembanding periode sebelumnya (hanya bila keduanya punya data), batasan, versi, dan waktu hitung; data di bawah minimum menjadi `INSUFFICIENT_DATA`. Median glukosa hanya per konteks puasa; tidak ada TIR/GMI/HbA1c; obat "belum dikonfirmasi" bukan "terlewat".
- **contextual** (`contextual-rules-v1`): maks 3 insight dari aturan tetap (jadwal obat belum dikonfirmasi, belum ada catatan makan setelah pukul 14, tujuan < 50% mulai Kamis, jeda catatan glukosa ≥ 3 hari, rangkaian ≥ 3 hari mencatat, perbandingan hari aktif pekan lalu). Tiap insight membawa `code` dan `evidence`.

## Sinkronisasi
Lihat [overview §7.2](../architecture/system-overview.md). Kode: `sync.service.ts` memanggil service domain yang sama; `hashOf()` membentuk `payload_hash`; `classify()` memetakan galat ke `CONFLICT | NEEDS_REVIEW | SYNC_FAILED`. `GET /api/me/sync/status` mengembalikan 50 kuitansi terakhir tanpa payload.

## Pencarian makanan dan pemindaian

| Modul | Rincian |
|---|---|
| food-discovery | `discover` (lokal → TKPI → OFF+USDA bila `external=true`), `web-search` (Brave; hanya tautan/cuplikan), `barcode/:code` (validasi GTIN lalu OFF), `foods/reference`, ukuran porsi `GET/POST /foods/:id/measures`, `nutrition/calculate`. Batas luar: 20 panggilan / 10 menit / pengguna. |
| food-reference | Pipeline TKPI: `scripts/tkpi/{parse,ingest,upload}.ts`; pencarian `reference.service.ts`. Tabel menyimpan `status` (`verified_auto` dipakai, `needs_review` disimpan tapi tidak dicari). 1.132 baris terurai, 1.037 `verified_auto` (menurut catatan P1; **jumlah baris di DB tidak diverifikasi pada audit ini**). `verified_auto` berarti konsisten secara internal (Atwater + jumlah proksimat), **bukan** diperiksa manusia. |
| food-vision | `scanLabel` (OCR → `parseLabel`), `identifyPhoto` (nama saja, tanpa kalori/porsi). Batas: 10 panggilan / 10 menit. |
| food-preferences | `kind ∈ {allergy, restriction, dislike, preference}`; `allergy`/`restriction` → `severity=strict`, lainnya `soft`. `checkFood()` mencocokkan **nama** (`NAME`) dan dugaan bahan lazim (`COMMON_INGREDIENT`); status `EXCLUDED | WARNING | NO_MATCH_FOUND`. **Tidak pernah berarti "aman"**. |

## Pengingat dan push
- **reminders**: `kind ∈ {medication, glucose, meal, activity, goal, custom}`, jam lokal + hari; `upcomingOccurrences()` menangani zona waktu/DST (jam yang tidak ada dimajukan).
- **push**: `PushDevice.token` unik global (token pindah akun bila didaftarkan akun lain); `unregister` **menghapus** token dan tidak butuh consent. Klien FCM (`fcm.client.ts`) menandatangani JWT RS256, host Google dipaku, mendukung `validate_only`. Pengirim pengingat (`push-dispatcher.ts`) sejak Fase 6 melewati pengguna yang mematikan push atau membisukan `REMINDER` di `notification_preferences` (`skippedByPreference`) dan mengirim data `{type: "reminder", action, refId}` (pengingat rencana kecil → `OPEN_COACHING` dengan ID rencana); notifikasi kotak masuk untuk pengingat dibuat tanpa push sehingga tidak ganda.

## Ekspor
`exportService.build` membaca 17 koleksi milik sendiri dalam satu transaksi `RepeatableRead`. Tidak menyertakan sesi, akun/kata sandi, token, `createHash`/`payloadHash`. **Cakupannya belum mencakup data P2/P3** (audit F-02).

## Agen (P2)

Berkas utama: `agent.service.ts` (siklus run), `agent.intent.ts` (maksud & query, murni), `food-identity.ts` (gerbang identitas makanan), `agent.graph.ts` (nutrisi), `activity.graph.ts` (aktivitas), `agent.tools.ts` (registri alat), `agent.safety.ts`, `personalization.ts`, `outcomes.ts`, `llm-text.ts`, `agent.stream.ts` (SSE), `agent-worker.ts`.

Registri alat (deny-by-default, `executeTool` satu-satunya jalur; semua penolakan dicatat di `agent_tool_calls`; anggaran 8 panggilan/run; batas waktu dan ukuran hasil per alat):

| Alat | Maksud yang diizinkan | Sumber |
|---|---|---|
| `get_food_preferences` | NUTRITION_ALTERNATIVES | `foodPreferencesService.activeFor` |
| `get_personalization` | NUTRITION_ALTERNATIVES, ACTIVITY_PLAN | `personalization.get` |
| `search_food_reference` | NUTRITION_ALTERNATIVES | `referenceService.search` |
| `search_user_foods` | NUTRITION_ALTERNATIVES | `nutritionService.searchFoods` |
| `get_activity_context` | ACTIVITY_PLAN | sesi 28 hari terakhir |
| `get_behavior_goals` | ACTIVITY_PLAN | tujuan aktif |

`userId` untuk alat selalu dari run milik sesi, bukan argumen. `requiredPermissions` ditegakkan di `executeTool` sejak 3.0 Fase 3 (tanpa consent → `PERMISSION_DENIED`, dicatat `DENIED`; audit F-10 ditutup).

Sebelum peringkat, kandidat harus lolos gerbang identitas: kata pertama pencarian ada di nama (`EXACT` bila semua kata ada, `CLOSE` bila ≥ separuh; selain itu dibuang dan dihitung `weakMatchesDropped`). Peringkat deterministik (graf nutrisi): `skor = 1/(posisi+1) + 0,1·jumlah_kecocokan [+0,15 bila dari katalog pengguna] + bonus_kelengkapan{COMPLETE 0,3; PARTIAL 0,1} + bonus_identitas{EXACT 0,5} − penalti_penolakan + bonus_dimakan`, ambil 3 teratas. Kandidat yang sudah ditawarkan pada giliran sebelumnya dikecualikan.

Teks: templat deterministik; bila ada kunci Mistral + consent `ai_text_generation`, model hanya **menulis ulang** penjelasan dari fakta tervalidasi, melalui `gateLlmText`, batas waktu 8 dtk, fallback ke templat dengan alasan dicatat di peristiwa `LLM_TEXT`.

## Percakapan (3.0 Fase 3)

Berkas: `conversation.router.ts` (router deterministik `router-v1`, murni), `conversation.parts.ts` (tipe bagian balasan, balasan tetap, ringkasan dari `stats-v1`), `conversation.service.ts` (thread, idempotensi `clientMessageId`, penyusunan balasan, hapus), `conversation.routes.ts`. Tabel `conversation_threads`, `conversation_messages`; consent H untuk semua endpoint, A/S dijawab sebagai bagian `consent_required`. Makanan, aktivitas, dan lanjutan diteruskan ke `agentService.createRun` dengan kunci idempotensi `conv-<clientMessageId>`; ringkasan memanggil `statisticsService.get`. Tes: `tests/unit/conversation.test.ts`, `tests/integration/conversation.test.ts`.

## Draf makan dan memori (3.0 Fase 4)

- `meal-drafts/`: `meal-text.parser.ts` (kalimat → kategori, makanan, jumlah, satuan; gram hanya bila disebut), `meal-draft.service.ts` (kandidat TKPI/katalog dengan gerbang identitas, takaran porsi milik pengguna, konfirmasi tepat-sekali lewat `nutritionService.create` dengan ID draf, pencarian web lewat alat agen yang tercatat sebagai run `MEAL_DRAFT_ENRICHMENT`).
- `memory/`: `memory.extract.ts` (pola preferensi yang dinyatakan; topik sensitif tidak diusulkan), `memory.service.ts` (usul → konfirmasi pengguna → aktif; ubah, hapus, hapus semua, jeda; dipakai hanya bila consent A dan ingatan aktif).
- `food-discovery/firecrawl.client.ts` (host dipaku, tanpa redirect, kunci di header) dan `web-nutrition.parser.ts` (per 100 g eksplisit, atau nilai per sajian yang diskalakan dengan gram atau rasio energi per 100 g yang dinyatakan halaman; dibaca per entri yang diawali nama makanan; uji kewajaran 4·P + 4·K + 9·L).
- Percakapan: rute `MEAL_LOG`, `PHOTO_MEAL`, `APPROVAL_HINT`, `PREFERENCE`; aktivitas memakai ingatan sebagai batasan yang hanya memendekkan (`applyActivityConstraints`).

## Rencana kecil & refleksi (3.0 Fase 5)

- `coaching/coaching.model.ts` (murni, `coach-rules-v1`): deteksi peluang dari fakta catatan 14 hari (makan siang/sarapan/makan malam jarang tercatat, rencana aktivitas yang sering belum terlihat, tujuan mingguan yang tertinggal, catatan jarang), varian yang lebih kecil bila ditolak, batas aman aktivitas (5 menit hingga sesi terpanjang 28 hari, maks 30), status per hari, minggu sasaran refleksi, pengamatan positif (hanya usaha), penyesuaian tujuan (hanya menurunkan; tujuan glukosa dikecualikan), pengakuan dan rentetan.
- `coaching/coaching.service.ts`: usulan dimaterialisasi sebagai `coaching_actions` `PROPOSED`; keputusan, umpan balik, dan konfirmasi tepat sekali lewat `coaching_events`; rekonsiliasi mencocokkan rencana dengan sesi aktivitas (jenis sama, durasi ≥ 50%) atau catatan makan (kategori sama), menarik bukti yang diarsipkan, mengarsipkan pengingat rencana yang selesai, dan menutup kartu JITAI terkait; refleksi memakai `weeklyService` dan `goalsService`; menyimpan refleksi menerapkan penyesuaian tujuan dengan `record_revisions`, preferensi waktu, dan (bila diizinkan) ingatan `ACTIVITY_TIME`.
- JITAI `jitai-policy-v2`: pemicu `COACHING_ACTION_DUE` (rencana hari ini yang belum terlihat; ditunda sampai waktunya; ditahan bila gagal validasi ulang), `WEEKLY_REVIEW_AVAILABLE` berhenti setelah refleksi terisi, pertanyaan klarifikasi setelah "kurang membantu", dan kelas keputusan `classify()`.
- Percakapan `router-v2`: rute `REFLECTION` ("minggu ini aku merasa gagal", "refleksi") dengan bagian `reflection` berisi fakta minggu berjalan.

## Komunitas
Lihat [overview §7.8](../architecture/system-overview.md). Aturan tambahan: check-in hanya hari ini atau ≤ 2 hari ke belakang (`MAX_BACKFILL_DAYS`), tidak di masa depan, dan dalam jendela tantangan; join tantangan memerlukan keanggotaan komunitas aktif; `memberCount` disembunyikan (`kurang dari 5`) bila kohort < 5.

### Siklus tantangan dan pengakuan (3.0 Fase 6)

Menutup audit F-04 (sebelumnya tantangan hanya dari seed migrasi).

- `community/lifecycle.model.ts` (murni, `challenge-lifecycle-v1`, zona bisnis `Asia/Jakarta`): `periodsToEnsure` menghitung periode berjalan dan berikutnya dari `anchor_date` + `cadence_days` templat; `statusOn`, `daysLeft`, `statusLabel` ("Mulai besok", "Mulai N hari lagi", "Berjalan · sisa N hari", "Berjalan · hari terakhir", "Selesai"); `completionFor` (`COMPLETED` bila hari aktif ≥ target, selain itu `PARTICIPATED`; `LEFT` bila keluar); `participantsLabel` ("kurang dari 5 peserta" bila < 5).
- `community/lifecycle.service.ts`: `runChallengeLifecycle(now)` membuat periode untuk semua komunitas × templat aktif (`createMany` + `skipDuplicates` pada unik `(community_id, template_id, starts_on)`), membuka `SCHEDULED` yang sudah mulai (notifikasi "Tantangan dimulai" ke peserta), menutup yang sudah lewat (`closed_at`), lalu membekukan hasil peserta (`completion_status`, `final_active_days`, `final_score`) dan mengirim "Tantangan selesai: Tuntas/Ikut serta" serta menyegarkan pengakuan. Setiap langkah memakai `updateMany` bersyarat status, jadi aman dijalankan bersamaan atau diulang. Berjalan tiap jam (`startChallengeLifecycle`) dan secara malas lewat `ensureFreshLifecycle()` (paling sering tiap 10 menit) saat daftar/detail/overview dibuka. Dimatikan dengan `CHALLENGE_LIFECYCLE_ENABLED=false` (stack uji).
- `community/recognition.model.ts` + `recognition.service.ts` (`recognition-v1`): tujuh aturan usaha (tantangan pertama, tantangan tuntas, 3 tantangan diikuti sampai selesai, refleksi pertama, 4 minggu refleksi berturut-turut, 5 hari rencana terlaksana, 7 hari berturut-turut ada catatan). `refresh` menyimpan yang baru tercapai (unik per pengguna) dan mengirim notifikasi `RECOGNITION`; dipanggil setelah join/check-in/hasil tantangan dan setelah refleksi. Tidak ada aturan berbasis nilai klinis, berat badan, atau peringkat.
- `community.service.ts` menambah `challenge()` (detail + `checkedInToday`), `history()`, `overview()` (sorotan Beranda: tantangan berjalan, atau pengakuan ≤ 7 hari), `privacy()`, `hideFromAllLeaderboards()`, `setHighlights()`, `chatSuggestions()` (bagian `challenges` di percakapan, rute `COMMUNITY` pada `router-v3`), dan `canSubscribeTopic()` untuk WebSocket. Join/check-in/visibilitas memancarkan `challenge.progress` ke pemilik dan `leaderboard.changed` ke topik tantangan (hanya bila alias tampil).

## Notifikasi dan realtime (3.0 Fase 6)

- `infrastructure/realtime/realtime.ts`: handler `websocket` untuk `Bun.serve<SocketData>`; topik `user:<id>` otomatis, topik lain lewat `setTopicGuard` (komunitas: anggota aktif saja), maks 20 topik per koneksi, sesi diperiksa ulang tiap ≤ 60 dtk (`4401 SESSION_ENDED`). `realtime.toUser`/`toTopic` dipakai modul lain; tanpa server (tes unit) keduanya no-op.
- `notifications/notification.service.ts`: `notify()` menghormati `muted_kinds`, menyimpan dengan `dedupe_key` (bentrok unik = sudah ada, dilewati), memancarkan `notification` lewat WebSocket, dan mengirim push FCM ke perangkat aktif bila `push_enabled` dan server terkonfigurasi. Push hanya membawa teks layar kunci umum per jenis dan data `{type, notificationId, action, refId}`; isi asli tidak pernah keluar ke Google. `notifyDueReminders()` membuat notifikasi `REMINDER` untuk kejadian pengingat dalam 3 menit terakhir (zona waktu pengguna, `upcomingOccurrences`); pengingat dari rencana kecil memakai teks "Rencana kecilmu hari ini."
- `startNotificationWorker(30_000, extra)` di `server.ts`: tiap 30 dtk memproses pengingat; tiap jam menjalankan `coachingService.nudgeReflections()` (notifikasi `REFLECTION` sekali per minggu sasaran, setelah pukul 18.00 lokal, untuk pengguna yang mencatat makan dalam 7 hari terakhir, memberi consent H + S + A, dan belum mengisi refleksi). Dimatikan dengan `NOTIFY_WORKER_ENABLED=false`.
- `coachingService` memancarkan `coaching.updated` setelah keputusan, umpan balik, konfirmasi, dan refleksi. Ekspor menyertakan `recognitions`, `notifications`, dan `notification_preferences`.

## ML
`dish.service.ts` + `modal.client.ts`. Tata kelola status model (`model_versions.status`):

| Status | Perilaku |
|---|---|
| `APPROVED` | mode LIVE: hasil menjadi `modelHint` (≥ 0,85) bila consent `model_inference` |
| `SHADOW`, `RESEARCH_ONLY` | mode bayangan: dijalankan & dicatat di `ml_inference_runs`, **tidak** dikembalikan ke pengguna |
| `DEPRECATED`/tidak ada | tidak dijalankan |

Klien Modal: hanya `https://*.modal.run`, bearer dari env, batas waktu 15 dtk, satu coba ulang untuk 5xx/jaringan, circuit breaker (3 gagal beruntun → terbuka 60 dtk), validasi skema + jumlah probabilitas ≤ 1,001, dan pencocokan `modelKey`/`modelVersion`/`artifactSha256` dengan registri (`VERSION_MISMATCH` bila berbeda). Persetujuan: `scripts/ml/set-model-status.ts` — `APPROVED` hanya bila akurasi uji tanpa duplikat ≥ 0,90 dan catatan ≥ 20 karakter.

## Intervensi (P3 awal)
Lihat [overview §7.6](../architecture/system-overview.md). Tanggapan: `OPENED` (bukan tanggapan; kartu hilang dari daftar tetapi masih bisa dinilai), `USEFUL, NOT_USEFUL, NOT_NOW, TOO_FREQUENT, ALREADY_DONE, DISMISSED, STOP_THIS_TYPE`. Akibat nyata yang terverifikasi di kode: `NOT_NOW` menunda (`snoozeMinutes`, default 120 menit); `STOP_THIS_TYPE` memasukkan pemicu ke `muted_triggers` dan membatalkan kartu terbuka sejenis; `TOO_FREQUENT` menurunkan jatah menjadi ≤ 1/hari dan ≤ 3/pekan; jeda (`pauseForHours`) membatalkan kartu proaktif yang terbuka. Jawaban pertama menang; mengulang jawaban yang sama aman (`replayed`). Isi pesan dari daftar tetap (bukan LLM). Catatan: `respond` melempar `CONSENT_REQUIRED` sebagai **409**, sedangkan modul lain memakai **403** (audit F-14).
