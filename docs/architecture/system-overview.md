# beOkay — Gambaran Sistem

> Dokumen rujukan utama. Dibuat dari audit kode pada **10 November 2026** (cabang `main`, commit dasar `21daa31` ditambah perubahan yang belum di-commit). Setiap pernyataan di sini diperiksa terhadap kode; bila sebuah fakta tidak bisa diverifikasi, ia ditandai **(belum terverifikasi)**.
> Dokumen lain di `docs/` adalah riwayat per tahap (P0–P3) dan bukti uji. Bila bertentangan dengan dokumen ini, kode adalah sumber kebenaran, lalu dokumen ini.

## 1. Apa itu beOkay

beOkay adalah platform **pencatatan kebiasaan harian** untuk orang dewasa dengan diabetes tipe 2 (atau yang sedang dalam penilaian). Aplikasi mobile (Android) membantu pengguna mencatat makanan, glukosa, aktivitas, obat, dan tujuan perilaku; menampilkan ringkasan **deskriptif**; dan menawarkan saran makanan/aktivitas yang selalu menunggu persetujuan pengguna.

Batas produk yang ditegakkan di kode, bukan hanya di copywriting:

| Batas | Penegakan di kode |
|---|---|
| Bukan alat diagnosis, bukan saran medis | `agent.safety.ts` menolak permintaan diagnosis, obat/dosis, klaim penyembuhan, gejala darurat; `FORBIDDEN_CLAIMS` menyaring semua teks keluaran |
| Tidak ada prediksi atau kesimpulan sebab-akibat | ringkasan/insight/tren hanya menghitung dari catatan sendiri; tidak ada korelasi |
| Nilai tidak diketahui ≠ 0 | kolom gizi `NULL`; hasil memuat `coverage` (`UNKNOWN`/`PARTIAL`/`COMPLETE`) dan `analyticsState` (`INSUFFICIENT_DATA`/`READY`) |
| Saran tidak mengubah catatan kesehatan | agen hanya membuat `planned_meals` / `activity_plans`; **tidak pernah** `meal_logs` atau `activity_sessions` |
| Tujuan bersifat perilaku | tidak ada tujuan yang memberi hadiah pada nilai glukosa rendah atau kalori rendah |
| Privasi komunitas | identitas publik = alias; tidak ada FK dari tabel komunitas ke profil/ukuran kesehatan |

Catatan cakupan populasi: `computeEligibility` (`health-profile/eligibility.ts`) menandai `eligible` hanya untuk **diagnosis = diagnosed, tipe = type_2, usia ≥ 18**. Blueprint produk (`ide.md`) juga menyebut prediabetes; kode belum membedakannya (lihat audit F-13).

## 2. Komponen dan topologi

```
┌────────────────────────────┐        HTTPS (Bearer)        ┌─────────────────────────────────────────────┐
│ Flutter app (Android)      │ ───────────────────────────► │ Bun API  (server/, satu proses)             │
│  Riverpod · go_router      │ ◄─────────────────────────── │  HTTP routes (Bun.serve)                     │
│  antrean offline terenkrip │         JSON / SSE           │  + Push dispatcher (interval 30 dtk)         │
│  Health Connect · FCM      │                              │  + Agent/outbox worker (3 dtk / 60 dtk)      │
└────────────────────────────┘                              └───────┬─────────────────────────────────────┘
                                                                    │ Prisma 7 (@prisma/adapter-pg)
                                                           ┌────────▼─────────┐
                                                           │ PostgreSQL 17     │  ekstensi: vector, pg_trgm
                                                           │ (pgvector image)  │
                                                           └──────────────────┘
Layanan luar (semua opsional; kosong = fitur nonaktif):
  SMTP (verifikasi email, reset sandi) · Mistral (OCR label, visi foto, embedding, penulis teks saran)
  Open Food Facts (tanpa kunci) · USDA FoodData Central · Tavily Search · FCM HTTP v1 (push)
  Modal (inferensi model pengenal hidangan) · UploadThing (hanya skrip operasional)
Artefak offline (bukan service di compose): ml/kaggle/train.py (pelatihan), ml/modal_app.py (deploy)
```

Poin penting arsitektur:

- **Satu proses API.** HTTP, dispatcher push, dan pekerja outbox hidup dalam proses yang sama (`server/src/server.ts`). Tidak ada antrean/worker terpisah, dan **tidak ada layanan Python/AI/ML di compose** (keputusan pemilik).
- **Runtime agen ada di TypeScript**, bukan LangGraph/FastAPI; state mesin disimpan di PostgreSQL.
- **Tidak ada penyimpanan gambar.** Foto dibaca ke memori, dikirim ke penyedia bila ada consent, lalu dibuang.

## 3. Teknologi (terverifikasi dari `package.json`, `pubspec.yaml`, `Dockerfile`)

| Lapisan | Teknologi |
|---|---|
| Runtime server | Bun 1.4.0 (image `oven/bun`), TypeScript `^7` |
| HTTP | `Bun.serve` dengan tabel `routes` (tanpa Express) |
| ORM / DB | Prisma `7.10.1` + `@prisma/adapter-pg`; PostgreSQL 17 (`pgvector/pgvector:pg17`) |
| Auth | Better Auth `1.7.18` (email+password, plugin `bearer`, adapter Prisma) |
| Validasi | Zod `^4.6.7` (skema `.strict()` pada hampir semua body) |
| Email | nodemailer (SMTP); Mailpit di dev/uji |
| Mobile | Flutter (Dart `^3.12.2`), `flutter_riverpod ^3.5`, `go_router ^18`, `http`, `flutter_secure_storage`, `mobile_scanner`, `image_picker`, `share_plus`, `flutter_local_notifications`, `health` (Health Connect), `firebase_messaging` |
| ML | MobileNetV3-Large (PyTorch) dilatih di Kaggle, dilayani lewat Modal (FastAPI) |

## 4. Struktur repositori

```
beOkay/
├── AGENTS.md · CLAUDE.md            aturan kerja agen (git, Docker, kredensial)
├── compose.yaml                     stack DEV (postgres, mailpit, api)
├── compose.test.yaml                stack UJI terisolasi (DB tmpfs)
├── compose.prod.yaml                stack PROD (postgres → migrate → api)
├── .env.example · .env.prod.example placeholder; .env* lain di-gitignore
├── server/                          API Bun
│   ├── index.ts → src/server.ts     titik masuk
│   ├── prisma/ (schema.prisma, migrations/ ×21)
│   ├── src/config/env.ts            validasi env (Zod)
│   ├── src/shared/                  error, handler HTTP, audit, logger, header keamanan, waktu lokal
│   ├── src/infrastructure/          database (Prisma), email (SMTP), queue (outbox)
│   ├── src/features/<modul>/        routes · service · repository · schema · model (≈30 modul)
│   ├── scripts/tkpi, scripts/ml     skrip operasional
│   └── tests/ (unit ×26, integration ×22)
├── app/                             Flutter (lib/core, lib/features/<modul>/{data,application,presentation}, test/)
├── ml/                              kaggle/train.py, modal_app.py (artefak, bukan service)
├── docs/                            dokumentasi (lihat docs/README.md)
└── ide.md                           blueprint produk 3.0 (spesifikasi target, bukan status)
```

## 5. Siklus sebuah permintaan

1. **Routing** — `Bun.serve({ routes })` di `src/server.ts` menggabungkan tabel rute tiap modul. Rute tak dikenal → `404 NOT_FOUND`.
2. **Pembungkus `route()`** (`shared/http/handler.ts`) — membuat `requestId` (UUID), menjalankan handler, menangkap semua galat, lalu menambah header `X-Request-Id`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, dan `Cache-Control: no-store` untuk `/api/*`. Satu baris log JSON per permintaan (tanpa isi badan).
3. **Autentikasi** — `authenticated()` (`features/auth/guard.ts`) memanggil `auth.api.getSession`; menolak (`401 UNAUTHENTICATED`) bila tidak ada sesi **atau email belum terverifikasi**. `userId` yang dipakai seterusnya **selalu** dari sesi.
4. **Badan permintaan** — `readJson()` menolak `Content-Type` selain JSON (415), badan > 64 KB (413), JSON rusak (400 `MALFORMED_JSON`), lalu `schema.parse` (galat Zod → `400 VALIDATION_ERROR` dengan daftar `path`/`code`, tanpa nilai). Foto dibaca lewat `readImage()` (maks 1,5 MB; tipe dari byte pertama, bukan header klien).
5. **Service** — memeriksa consent (`consentService.requireConsent`), membuka transaksi Prisma, menulis data + `recordAudit` (+ `outbox.enqueue` bila perlu) dalam transaksi yang sama.
6. **Respons** — badan JSON langsung (tanpa amplop) untuk sukses; untuk galat selalu `{ "error": { "code", "message", "requestId", "details"? } }`. Kode status umum: 400, 401, 403 (`CONSENT_REQUIRED`), 404, 409 (`VERSION_CONFLICT`, `IDEMPOTENCY_CONFLICT`), 413, 415, 422, 429, 500 (`INTERNAL_ERROR`, tanpa detail).

## 6. Pola lintas modul (invarian)

### 6.1 Kepemilikan data
Semua query dibatasi `user_id` dari sesi. ID dari klien tidak dipercaya untuk kepemilikan: `find(userId, id)` selalu menyertakan `userId`; rekaman milik orang lain menghasilkan `404`, bukan `403`.

### 6.2 Consent per tujuan
Sembilan tujuan (`consent/consent.policy.ts`, versi kebijakan **`1.0`**, berlaku 2026-11-08, teksnya masih **draf yang wajib ditinjau pihak berwenang**):

| Tujuan | Wajib | Dipakai oleh |
|---|---|---|
| `health_data_processing` | ya | hampir semua modul pencatatan, pencarian makanan, pemindaian, sinkronisasi, pengingat, push, agen |
| `descriptive_summaries` | ya | `today`, ringkasan harian/mingguan, tren, insight kontekstual, ringkasan per domain |
| `product_analytics` | tidak | belum dipakai kode (hanya terdaftar) |
| `personalized_ai` | tidak | agen, rekomendasi, personalisasi, intervensi, rekonsiliasi hasil |
| `ai_text_generation` | tidak | penulisan ulang teks saran oleh Mistral |
| `model_inference` | tidak | pengiriman foto ke Modal (bayangan/LIVE) |
| `community_membership` | tidak | bergabung/lihat komunitas |
| `challenge_participation` | tidak | ikut tantangan & check-in |
| `leaderboard_visibility` | tidak | tampil di papan peringkat |

Aturan: satu consent aktif per `(user, tujuan)` (indeks unik parsial `consent_records_one_active_per_purpose`); consent versi lama berstatus `reconsent_required` dan **tidak** memenuhi `requireConsent`; menarik consent menutup baris aktif (tidak menghapus data). Penarikan `health_data_processing` menghentikan sinkronisasi (`403 CONSENT_REQUIRED`), push, dan tampilan data; ekspor data **sengaja tidak** bergantung pada consent.

### 6.3 Pembuatan idempoten (client-generated UUID)
Pencatatan (makan, glukosa, aktivitas, obat, tujuan, check-in) menerima `id` UUID dari klien. Server menghitung `create_hash = sha256(JSON(input))`. Pengulangan dengan isi sama → mengembalikan baris yang ada; isi berbeda → `409 IDEMPOTENCY_CONFLICT`. Balapan antar permintaan ditangani lewat `P2002` (unique violation) lalu dibaca ulang.

### 6.4 Koreksi dengan versi dan revisi
`PATCH` wajib memuat `expectedVersion` dan `reason`. Update memakai `updateMany({ where: { id, userId, version } })`; bila `count ≠ 1` → `409 VERSION_CONFLICT`. Sebelum perubahan, snapshot versi lama ditulis ke `record_revisions` (`UNIQUE(<fk>, version)`). **Tidak ada hapus keras** untuk catatan kesehatan: `archived: true` mengisi `archived_at`.

### 6.5 Satuan, waktu, dan zona
- Glukosa disimpan dalam `value_mg_dl NUMERIC(16,7)` (kanonik) **dan** nilai/satuan asli. Faktor `18.016` mg/dL per mmol/L (`preferences/glucose-units.ts`). Tampilan mengikuti `user_settings.glucose_unit`; domain numerik yang diterima 1–2000 mg/dL (bukan batas klinis).
- Semua waktu `TIMESTAMPTZ`. Zona per pengguna (`user_settings.timezone`, default `Asia/Jakarta`); `localRecordTime()` menurunkan `localDate`/`localTime`. `recordTimestamp` menolak waktu > 5 menit di masa depan, tahun < 1900, dan tanggal yang tidak valid.
- Ukuran memakai `NUMERIC`/`Decimal`; `JSONB` hanya untuk metadata variabel (snapshot, payload agen, hasil sinkronisasi).

### 6.6 Audit dan proyeksi turunan
`recordAudit()` menulis `audit_events` dan, bila `eventType` berawalan `meal_`, `glucose_`, `activity_`, `medication_`, `goal_`, `consent_`, `preferences_`, atau `food_`, menandai `summary_projections` pengguna `STALE`. Proyeksi adalah cache turunan (boleh dibuang dan dihitung ulang); respons tetap dihitung baru.

### 6.7 Outbox transaksional
`outbox_events` ditulis **dalam transaksi yang sama** dengan perubahan data (`dedupe_key` unik). Pekerja (`startAgentWorker`) menguras tiap 3 dtk dengan `FOR UPDATE SKIP LOCKED`, backoff eksponensial dasar 5 dtk, maksimal 5 percobaan, lalu `DEAD`. Pengiriman minimal-satu-kali; penangan harus idempoten. Jenis peristiwa yang ditangani: `outcome.observed`, `outcome.retracted` (mengubah personalisasi), serta `recommendation.decided`, `recommendation.feedback`, `intervention.responded` (saat ini no-op).

### 6.8 Keselamatan berlapis untuk saran
1. `screenRequest(message)` (`safety-policy-v2`, sejak 3.0 Fase 7) — dijalankan pertama oleh router percakapan dan `createRun`, sebelum maksud ditentukan. Teks dinormalisasi (singkatan, typo, huruf berulang, reduplikasi, sebagian kosakata Jawa/Sunda, akhiran -ku/-nya), lalu sepuluh aturan berurutan: menyakiti diri, gejala darurat (termasuk gugus tanda hipoglikemia), angka glukosa ekstrem (< 70 atau ≥ 300 mg/dL; < 3,9 atau ≥ 16,7 mmol/L), keluhan yang perlu diperiksa (luka kaki, kesemutan, haus/sering kencing), nyeri/cedera, eskalasi intensitas, saran obat/dosis, permintaan diagnosis, klaim kesehatan, pembatasan ekstrem. Tiga yang pertama ditandai mendesak.
2. `validateCandidate()` — kandidat tanpa nama/sumber, atau gizi di luar rentang masuk akal, tidak boleh ditawarkan.
3. Filter alergi/pembatasan keras (`checkFood` berdasarkan **nama** makanan) sebelum peringkat.
4. `explanationIsSafe()` — gerbang klaim terlarang pada teks apa pun, termasuk keluaran LLM.
5. `gateLlmText()` — teks LLM harus: tidak kosong, ≤ 420 karakter, tanpa tautan/markup, lolos gerbang klaim, menyebut nama kandidat, dan **tidak memuat angka baru**; jika gagal, dipakai templat.
6. Persetujuan pengguna tepat-sekali (`recommendations.version` + `recommendation_decisions UNIQUE(user_id, operation_id)`).

Keterbatasan yang diakui: kebijakan berbasis kata kunci, belum ditinjau klinisi. Korpus adversarial 99 kalimat (`tests/fixtures/safety-corpus.ts`) hanya bukti regresi. Kelemahan yang diketahui dan pertanyaan untuk klinisi ada di [paket tinjauan](../research/safety-clinical-review-packet.md).

## 7. Alur utama

### 7.1 Registrasi → onboarding
`POST /api/auth/sign-up/email` → email verifikasi (Mailpit di dev) → pengguna **tidak** masuk otomatis (`autoSignIn: false`) → verifikasi → masuk (`set-auth-token` pada header respons dipakai sebagai Bearer). `GET /api/me/onboarding` menurunkan state dari data nyata, bukan dari kolom status:

`EMAIL_VERIFICATION_PENDING → NOT_STARTED → CONSENT_PENDING → PERSONAL_PROFILE_PENDING → HEALTH_PROFILE_PENDING → PREFERENCES_PENDING → READY_TO_COMPLETE → COMPLETED`

Router Flutter (`core/router/redirect.dart`) memetakan state itu ke layar dan mencegah loncat ke depan.

### 7.2 Pencatatan online dan offline
Online: `POST /api/me/{meals|glucose|activities|...}` dengan UUID klien. Offline: `AccountScopedRepository.write()` menangkap galat jaringan lalu menyimpan `QueuedOperation` ke penyimpanan aman per akun (`beokay.queue.<accountId>`); `SyncController` mengirim tiap 30 dtk/saat aplikasi dibuka ke `POST /api/me/sync/operations` (maks 50 operasi, `operationId` unik). Server memanggil **service domain yang sama** (tanpa logika ganda) dan mengembalikan status per operasi:

| Status | Arti | Tindakan klien |
|---|---|---|
| `SYNCED` | berhasil | hapus dari antrean |
| `CONFLICT` | 409 (mis. versi berubah, `OPERATION_ID_REUSED`) | tampil di layar Sinkronisasi; pengguna memutuskan |
| `NEEDS_REVIEW` | 4xx lain / validasi / `CONSENT_REQUIRED` | idem |
| `SYNC_FAILED` | galat sementara | dicoba lagi; **tidak** disimpan sebagai kuitansi |

Kuitansi (`sync_operations UNIQUE(user_id, operation_id)`, `payload_hash`) membuat pengulangan idempoten. Domain yang boleh diantrekan: `meal`, `glucose`, `activity`, `medication_intake`, `goal_checkin`. Koreksi tertunda untuk rekaman yang sama digabung (nilai terbaru menang, `expectedVersion` pertama dipertahankan). Penarikan consent menghapus antrean lokal.

### 7.3 Pencarian makanan dan gizi
`GET /api/me/foods/discover?q=&external=&hideExcluded=` — urutan: katalog sendiri + katalog bersama → referensi **TKPI** (hibrida leksikal `pg_trgm` + semantik `pgvector`/`mistral-embed`, digabung Reciprocal Rank Fusion, ambang kemiripan 0,75, hanya baris `verified_auto`) → bila `external=true`: Open Food Facts + USDA. Setiap hasil diberi `preferenceCheck` (alergi/pembatasan berdasarkan nama). Penghitung porsi (`POST /api/me/nutrition/calculate`) tidak menyimpan apa pun; berat tidak diketahui → nilai kosong (`PORTION_WEIGHT_UNKNOWN`), bukan tebakan.

### 7.4 Pemindaian
- **Label** (`/foods/scan/label`): Mistral OCR → `parseLabel` (parser deterministik) → kandidat per 100 g; pengguna wajib memeriksa.
- **Foto** (`/foods/scan/photo`): Mistral visi hanya menamai makanan (skema `photoOutput`), dicocokkan ke katalog + TKPI dengan `referenceCovers` (setiap kata penting harus ada). Paralel: `dishService.assist()` — model Modal; hanya `APPROVED` + consent `model_inference` yang menghasilkan `modelHint` (probabilitas terkalibrasi ≥ 0,85, "perkiraan", tidak pernah dicatat otomatis). Model bukan-`APPROVED` hanya dijalankan **bayangan** untuk evaluasi.

### 7.5 Agen rekomendasi
```
POST /api/me/agent/runs  (idempotencyKey, message, query?, previousRunId?)
  CREATED → VALIDATING → [screenRequest: BLOCKED | NEEDS_CLINICAL_REVIEW → selesai]
          → klasifikasi maksud (NUTRITION_ALTERNATIVES | ACTIVITY_PLAN | UNSUPPORTED | FOLLOW_UP_*)
          → RUNNING: graf (gather_context → retrieve_candidates → validate_and_filter → rank), maks 8 panggilan alat
          → rekomendasi OFFERED (maks 3) + run WAITING_FOR_USER   (kedaluwarsa 24 jam)
POST /recommendations/:id/decision {operationId, decision: ACCEPT|REJECT, expectedVersion}
  ACCEPT → planned_meals(PLANNED) | activity_plans(CONFIRMED) ; REJECT → bobot penolakan di personalisasi
POST /recommendations/:id/feedback {CONSUMED|NOT_CONSUMED|COMPLETED|SKIPPED}   (laporan sendiri)
Pekerja: rekonsiliasi hasil TERUKUR (meal_logs / activity_sessions) → recommendation_outcomes → outbox → personalisasi (±1)
```
Status run: `CREATED, VALIDATING, RUNNING, WAITING_FOR_USER, COMPLETED, FAILED, BLOCKED, CANCELLED, EXPIRED`. Run macet > 120 dtk menjadi `FAILED`; penarikan consent mengubah run menunggu menjadi `BLOCKED` dan rekomendasi `INVALIDATED`. Percakapan multi-giliran lewat `parent_run_id` (maks 20 giliran) dengan pola "kenapa" dan "yang lain" yang dikenali regex. Aliran SSE (`?async=1` lalu `GET /runs/:id/stream`, polling 400 ms, maks 45 dtk, `Last-Event-ID` untuk sambung ulang).

Personalisasi (`pref-rules-v2`) **deterministik, bukan pembelajaran mesin**: penolakan menambah bobot kata nama makanan (maks 5; penalti 0,6/bobot), makanan yang terukur dimakan menambah bonus (0,2/bobot). Pengguna dapat mereset (`DELETE /api/me/personalization`); setiap perubahan tercatat di `personalization_events`.

### 7.6 Intervensi proaktif (P3 tahap awal)
`POST /api/me/interventions/evaluate` → `decide()` (fungsi murni `jitai-policy-v1`) → **selalu** mencatat keputusan, termasuk `NO_INTERVENTION` beserta alasan (`CONSENT_MISSING`, `COACHING_PAUSED`, `TRIGGER_MUTED`, `NO_ACTIVE_GOAL`, `ALREADY_DONE_TODAY`, `SNOOZED`, `DUPLICATE`, `REPEAT_SUPPRESSED`, `QUIET_HOURS`, `DAILY_LIMIT`, `WEEKLY_LIMIT`, `TOO_SOON`). Default: jam tenang 22:00–07:00 (menit 1320–420), maks 2/hari dan 7/pekan, jeda minimum 3 jam. Pemicu `USER_REQUESTS_SUPPORT` dimulai pengguna sehingga tidak memakai jatah. **Belum ada pemicu otomatis dari server** dan kanal hanya in-app.

### 7.7 Pengingat dan push
Pengingat disimpan di server (`reminders`); klien menjadwalkan notifikasi lokal dari `GET /api/me/reminders/upcoming` (maks 60 sekaligus). Bila FCM dikonfigurasi dan pengguna mendaftarkan perangkat, dispatcher server (30 dtk) mengirim push: buku besar `push_deliveries UNIQUE(reminder_id, device_id, scheduled_at)` mencegah kirim ganda; pengingat terlambat > 3 menit dilewati; **teks layar kunci generik** (tanpa judul pengguna, nama obat, atau angka). Token mati (`UNREGISTERED` dll.) menonaktifkan perangkat. Maks 5 perangkat aktif per pengguna.

### 7.8 Komunitas dan tantangan
Wilayah = 38 provinsi (`regions`), satu komunitas bawaan per provinsi. Alias 3–20 karakter, unik per komunitas, tanpa surel/nomor telepon/kata penyamar staf. Skor `score-v1`: 50 poin hari aktif (sesi ≥ 10 menit; proporsional terhadap target, tidak menambah di atas target), 30 poin check-in sukarela, 20 poin partisipasi. Buku besar `score_events` **append-only** (trigger `score_events_immutable` menolak UPDATE); koreksi = baris pembalikan. Papan peringkat hanya alias + skor + peringkat, ditekan bila kohort < 5, dan opt-in per tantangan.

## 8. Keamanan dan privasi — ringkasan kontrol

| Area | Kontrol |
|---|---|
| Sesi | Better Auth, masa berlaku 7 hari, perpanjang tiap 1 hari; token di Keystore/Keychain via `flutter_secure_storage` |
| Kata sandi | 10–128 karakter, verifikasi email wajib, reset berlaku 1 jam dan mencabut semua sesi |
| Rate limit auth | 120/menit umum; sign-in 5, sign-up 5, reset 3, kirim verifikasi 3, ganti sandi 5 per menit (penyimpanan **memori**) |
| IP klien | header `x-beokay-client-ip` selalu ditimpa server; `X-Forwarded-For` dipercaya hanya bila `TRUST_PROXY=true` |
| Egress | host dipaku per klien (`api.mistral.ai`, `api.tavily.com`, OFF, USDA, `*.modal.run`), `redirect: "error"`, batas ukuran balasan, batas waktu |
| Hasil web | hanya judul/tautan/cuplikan https tanpa kredensial/port/host IP; `usableForNutrition: false` |
| Gambar | tidak disimpan; ukuran maks 1,5 MB; tipe dari byte |
| Push | teks generik; token tidak pernah dikembalikan utuh (`…xxxxxx`) |
| Ekspor | `GET /api/me/export` (5/jam), tanpa sesi/kata sandi/hash internal — **lihat audit F-02 untuk cakupan yang belum lengkap** |
| Kontainer prod | `read_only`, `cap_drop: ALL`, `no-new-privileges`, jaringan DB `internal`, batas memori 512 MB |

## 9. Asumsi dan batas yang perlu diketahui

- **Satu instans API.** Pembatas laju (agen 20/10 mnt, pemindaian 10/10 mnt, pencarian luar 20/10 mnt, ekspor 5/jam, auth), cache embedding, dan circuit breaker Modal tersimpan **di memori proses**. Menjalankan >1 replika membuat batas tidak konsisten; restart me-reset semuanya.
- **Android saja.** Keputusan pemilik: tidak ada iOS/HealthKit.
- **Satu bahasa/lokal.** Antarmuka `id-ID`; API hanya menerima `id-ID` (CHECK DB masih mengizinkan `en-US`).
- **Tantangan komunitas hanya dari seed migrasi** (lihat audit F-04).
- **Tidak ada observabilitas agregat, SLO, atau pemulihan bencana** (P3-11 `NOT_STARTED`).
