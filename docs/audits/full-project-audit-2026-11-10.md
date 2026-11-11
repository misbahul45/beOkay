# Audit Menyeluruh Proyek beOkay — 10 November 2026

> Cakupan: seluruh repositori (`server/`, `app/`, `ml/`, `docs/`, compose, konfigurasi). Metode: membaca kode sumber dan migrasi, menjalankan typecheck/analisis/tes, memindai berkas ter-track, dan mencocokkan klaim dokumen dengan kode. Dokumentasi hasil audit: [system-overview](../architecture/system-overview.md), [server-modules](../reference/server-modules.md), [schema-reference](../database/schema-reference.md), [endpoint-reference](../api/endpoint-reference.md), [mobile-app](../architecture/mobile-app.md), [runbook](../operations/runbook.md).
> Audit ini **tidak mengubah kode**. Satu-satunya berkas yang ditambahkan adalah dokumentasi di `docs/`. Tidak ada `git add/commit/push`.

## 0. Pembaruan status (10 Nov 2026, setelah audit)

| Temuan | Status | Bukti |
|---|---|---|
| F-01 Hapus akun/data | **DITUTUP** | `POST /api/me/account/delete`, layar Pengaturan → Privasi & data; `tests/integration/account.test.ts` memeriksa setiap tabel ber-`user_id` kosong setelah hapus; `identity_flows_test.dart` (N) |
| F-02 Ekspor tidak lengkap | **DITUTUP** | `beokay-export-v2`; tes membandingkan semua tabel ber-`user_id` dengan daftar ekspor + pengecualian beralasan |
| F-10 `requiredPermissions` alat | **DITUTUP** | `executeTool` memeriksa consent setiap alat; tanpa consent → `PERMISSION_DENIED` dan tercatat `DENIED` (`tests/integration/conversation.test.ts`) |
| F-03 Rilis Android | **SEBAGIAN DITUTUP** | `id.beokay.app`, `INTERNET` di manifes utama, penandatanganan via `key.properties`, guard `API_BASE_URL=https://` — terverifikasi pada APK rilis. Tersisa: kunci rilis milik pemilik dan pendaftaran Firebase |



beOkay adalah basis kode yang **disiplin dan konsisten pada prinsip keselamatan datanya**: nilai tak diketahui tidak dijadikan nol, saran tidak mengubah catatan kesehatan, consent diperiksa per tujuan di lapisan service, penulisan bersifat idempoten dan berversi, dan seluruh keluaran model bahasa melewati gerbang deterministik. Suite otomatis hijau (backend 238/238, Flutter 157/157, typecheck dan analisis bersih).

Namun proyek **belum siap untuk pengguna nyata**. Empat hal paling penting:

| # | Temuan | Mengapa penting |
|---|---|---|
| F-01 | **Tidak ada fitur hapus akun/data**, padahal teks consent menjanjikannya dan rencana P3 mencatatnya sebagai ada | hak penghapusan data kesehatan; klaim dokumen tidak sesuai kode |
| F-02 | **Ekspor data tidak mencakup tabel P2/P3** (rekomendasi, rencana, personalisasi, komunitas, intervensi, perangkat push, hasil terukur) | hak portabilitas tidak lengkap |
| F-03 | **Aplikasi Android belum bisa dirilis**: `applicationId` placeholder, rilis ditandatangani kunci debug, `INTERNET` tak terjamin di rilis, tidak ada `google-services.json`, API default `localhost` | build rilis kemungkinan tidak dapat memakai jaringan/push |
| F-04 | **Siklus hidup tantangan tidak ada**: satu tantangan 28 hari di-seed oleh migrasi, tidak ada kode pembuat/penutup | fitur komunitas mati setelah jendela itu berakhir |

Klasifikasi keseluruhan (memakai kosakata laporan proyek): **`FUNCTIONALLY_COMPLETE_FOR_DEVELOPMENT`, `NOT_PRODUCTION_READY`**.

## 2. Verifikasi yang dijalankan

| Pemeriksaan | Perintah | Hasil |
|---|---|---|
| Typecheck server | `docker compose exec api bun run typecheck` (`tsc --noEmit`) | tanpa keluaran galat |
| Tes backend | `docker compose -f compose.test.yaml run --rm --build tester` (DB uji terisolasi, lalu `down -v`) | **238 lulus, 0 gagal, 1.705 `expect`, 48 berkas, 20,51 dtk** |
| Analisis Flutter | `flutter analyze` | *No issues found* |
| Tes Flutter | `flutter test` | **157 lulus** |
| Pemindaian rahasia (regex) | pola kunci Google/OpenAI/Slack/GitHub/AWS/PEM/`private_key` atas seluruh berkas ter-track | **0 temuan** |
| Berkas env ter-track | `git ls-files` | hanya `.env.example` dan `.env.prod.example` |
| Kata sandi literal di tes/skrip | grep | 1 hasil: `'${_password}x'` (variabel tes, bukan literal) |
| Berkas milik root | `find -user root` | 5 berkas kosong di `server/` (F-07) |

**Tidak dijalankan / tidak diverifikasi:** koleksi Bruno; pengujian di emulator atau perangkat; `prisma migrate diff`; stack prod; panggilan nyata ke Mistral/Modal/FCM/SMTP/OFF/USDA/Brave; pemindai rahasia khusus (gitleaks/trufflehog); build rilis APK dan manifes gabungan rilis; jumlah baris `food_reference` di DB dev; status baris `model_versions` di DB dev. Angka-angka tersebut di dokumen lain berasal dari laporan proyek, bukan dari audit ini.

## 3. Temuan

Keparahan: **Tinggi** = memblokir rilis/memengaruhi hak pengguna; **Sedang** = risiko operasional atau fungsional yang nyata; **Rendah** = kualitas/konsistensi; **Info** = catatan.

### F-01 — Tidak ada penghapusan akun atau data · **Tinggi**
- **Bukti:** tidak ada rute `DELETE /api/me`, Better Auth `deleteUser` tidak diaktifkan (`auth.ts`), dan tidak ada layar hapus di Flutter (`settings_screen.dart`: hanya Preferensi, Tampilan, Persetujuan data, Keamanan akun, Keluar). `consent.policy.ts:37` menyatakan "kamu bisa meminta penghapusan di Privasi & data" — **layar itu tidak ada**. `docs/reports/p3-execution-plan.md:16` mencantumkan "hapus akun (cascade)" sebagai bagian P3-10 yang ada; yang ada hanya `ON DELETE CASCADE` pada FK.
- **Dampak:** pengguna tidak dapat menghapus data kesehatannya; janji pada teks persetujuan tidak dapat dipenuhi; klaim dokumen tidak benar.
- **Rekomendasi:** (a) implementasikan penghapusan akun terkonfirmasi ulang (kata sandi/email) yang memanggil `auth.api.deleteUser` dan memverifikasi cascade pada **semua** tabel, termasuk `ml_inference_runs`/`audit_events` (`SET NULL`) dan `outbox_events`; (b) tambahkan tes cascade; (c) sampai itu ada, ubah teks consent dan dokumen P3 agar tidak menjanjikan penghapusan mandiri.

### F-02 — Ekspor data tidak lengkap · **Tinggi**
- **Bukti:** `export.service.ts` mengekspor 17 koleksi (akun, profil, profil kesehatan, pengaturan, onboarding, consent, makanan, ukuran porsi, makan, glukosa, aktivitas, obat, tujuan, revisi, preferensi makanan, pengingat, audit). **Tidak ada:** `recommendations`, `recommendation_decisions/feedback/outcomes`, `planned_meals`, `activity_plans`, `agent_runs` (+ peristiwa), `personalization_profiles/events`, `community_memberships`, `challenge_participants/checkins`, `score_events`, `intervention_decisions/preferences`, `push_devices`, `sync_operations`, `ml_inference_runs`. Audit dibatasi `take: 5000` (`export.service.ts:53`) tanpa menandai pemotongan. Catatan `notice` hanya menyebut "ringkasan turunan, sesi, dan kata sandi" yang dikecualikan.
- **Dampak:** hak akses/portabilitas data tidak terpenuhi untuk data yang dihasilkan P2/P3, padahal sebagian di antaranya (preferensi yang dipelajari, keputusan atas saran) bersifat personal.
- **Rekomendasi:** tambahkan koleksi tersebut (kecuali yang murni internal: `outbox_events`, token push utuh), naikkan `EXPORT_FORMAT_VERSION`, tandai `truncated` pada audit, dan tambahkan tes "setiap tabel ber-`user_id` muncul di ekspor atau ada di daftar pengecualian eksplisit" agar tabel baru tidak terlupa.

### F-03 — Aplikasi Android belum siap rilis · **Tinggi**
- **Bukti:** `build.gradle.kts:21` `applicationId = "com.example.app"` (dengan `TODO`); `:35` rilis memakai `signingConfigs.getByName("debug")`; manifes utama tidak mendeklarasikan `INTERNET` (hanya `src/debug` dan `src/profile`); `google-services.json` tidak ada sehingga plugin Firebase tidak diterapkan; `app_config.dart:4` default `http://localhost:3000`. Hanya build debug yang ada di `app/build`, sehingga manifes gabungan rilis **tidak dapat diperiksa** — plugin Firebase/lainnya mungkin menambahkan `INTERNET` saat merge, tetapi itu **belum terverifikasi**.
- **Dampak:** build rilis mungkin tidak punya akses jaringan, tidak dapat diterbitkan (kunci debug / ID `com.example`), dan push tidak dapat berfungsi.
- **Rekomendasi:** tetapkan `applicationId` final dan daftarkan di Firebase; buat keystore rilis (di luar repo) dan `signingConfigs.release`; tambahkan `<uses-permission android:name="android.permission.INTERNET"/>` ke manifes utama; bangun APK rilis dan periksa `aapt dump permissions`; dokumentasikan `--dart-define=API_BASE_URL=https://…`.

### F-04 — Tantangan komunitas tidak punya siklus hidup · **Sedang**
- **Bukti:** satu-satunya `INSERT INTO "challenges"` ada di `20261109110000_community/migration.sql:96-97` dengan `CURRENT_DATE … CURRENT_DATE + 27`, status `OPEN`. Grep `challenge.(create|update|upsert)` pada `src/` tanpa hasil; tidak ada kode yang menutup tantangan atau membuat yang baru. `joinChallenge` menolak setelah `ends_on` (`CHALLENGE_CLOSED`).
- **Dampak:** jendela berakhir 27 hari setelah hari migrasi itu diterapkan (pada DB dev: sekitar awal Desember 2026, tergantung tanggal penerapan yang **tidak diperiksa**; pada prod baru: 28 hari sejak deploy). Setelah itu tab Komunitas tidak punya tantangan aktif. Selain itu, jendela bergantung pada tanggal migrasi dijalankan, bukan pada keputusan produk.
- **Rekomendasi:** tentukan model (tantangan berulang otomatis / dibuat admin), tambahkan mekanisme pembuat+penutup yang idempoten, dan hentikan penggunaan `CURRENT_DATE` di migrasi untuk data bisnis.

### F-05 — Seluruh pembatas laju dan cache hidup di memori proses · **Sedang**
- **Bukti:** Better Auth `rateLimit.storage: "memory"`; `Map` per-proses di `agent.service.ts:26` (20/10 mnt), `food-vision.service.ts:62` (10/10 mnt), `food-discovery.service.ts:26` (20/10 mnt), `export.service.ts:8` (5/jam), `dish.service.ts:14` (pemanasan), cache embedding `reference.service.ts:21`, circuit breaker Modal. Entri `Map` per pengguna tidak pernah dibersihkan untuk pengguna yang tidak aktif lagi.
- **Dampak:** restart me-reset batas (termasuk batas login); >1 replika membuat batas tidak konsisten; pertumbuhan memori lambat per pengguna unik. Ini juga akar kegagalan acak tes saat suite diulang (G-01).
- **Rekomendasi:** dokumentasikan asumsi satu replika (sudah dilakukan di dokumen ini), bersihkan `Map` secara berkala, dan pindahkan batas penting (auth, agen) ke penyimpanan bersama (Postgres/Redis) sebelum menambah replika.

### F-06 — Tidak ada CI · **Sedang**
- **Bukti:** tidak ada `.github/`, `.gitlab-ci.yml`, atau sejenisnya. Tes, typecheck, dan analisis hanya dijalankan manual.
- **Rekomendasi:** pipeline minimum: typecheck + `compose.test.yaml` + `flutter analyze/test` + pemindaian rahasia (gitleaks) pada setiap PR. Mengingat aturan "tidak boleh commit oleh agen", pipeline inilah penjaga mutu yang tersisa.

### F-07 — Berkas sampah dan artefak besar ter-track · **Rendah–Sedang**
- **Bukti:** lima berkas **nol byte milik `root`** sudah di-stage (`A`): `server/crash-a.ts`, `crash-b.ts`, `live.ts`, `live2.ts`, `dish.jpg` (stempel waktu 10 Nov 05:52–06:49 WIB; kemungkinan sisa eksperimen yang dijalankan di dalam container — asal pastinya tidak diperiksa). Ini melanggar aturan "tidak ada berkas root di bind mount". Juga ter-track: `docs/repomix-output.xml` (249 KB, paket otomatis seluruh kode — sudah basi) dan `ide.md` (168 KB, blueprint).
- **Rekomendasi:** `git rm --cached` + hapus kelima berkas kosong (direktorinya milik pengguna sehingga `rm` biasa berhasil); pertimbangkan menghapus `docs/repomix-output.xml` atau meng-ignore-nya; pindahkan `ide.md` ke `docs/` dengan nama yang jelas. Agen tidak menghapusnya karena di luar permintaan audit.

### F-08 — Dokumen dan konfigurasi usang atau menyesatkan · **Sedang**
| Lokasi | Isi usang | Keadaan sebenarnya |
|---|---|---|
| `AGENTS.md:15` | `app/` "scaffold bawaan, belum dikerjakan" | aplikasi lengkap (172 berkas Dart di `lib/`, 29 di `test/`, 157 tes) |
| `AGENTS.md:19-21` | "Cakupan saat ini": hanya identitas; "Belum… tabel pencatatan, UI Flutter, ringkasan/insight" | ada 21 migrasi, 51 model, ±30 modul, P0–P3 awal |
| `AGENTS.md:60`, `compose.yaml:10` | ekstensi pgvector "belum aktif" | `CREATE EXTENSION vector, pg_trgm` di migrasi `…070000`, indeks HNSW aktif |
| `.env.example:25,40` | LLM/Mistral "belum dipakai kode P0/P1" | Mistral dipakai (OCR, visi, embedding, teks saran); blok `LLM_*` **tidak dibaca kode mana pun** |
| `server/package.json:31` | `auth:generate --config src/lib/auth.ts` | berkas itu tidak ada; auth di `src/features/auth/auth.ts` |
| `schema.prisma:3` | domain P0 "menunggu Data Dictionary" | tabel domain sudah dibuat |
| `docs/reports/p3-execution-plan.md:16` | "hapus akun (cascade)" | tidak ada (F-01) |
| `server/README.md`, `app/README.md` | boilerplate `bun init` / `flutter create` | — ; **tidak ada `README.md` di root repo** |
| Angka tes di `docs/` (69, 97, 127, 151, 219…) | riwayat per tahap | sekarang 238 / 157 |
- **Rekomendasi:** perbarui `AGENTS.md` (instruksi untuk agen — keputusan pemilik), hapus/ganti `LLM_*`, perbaiki skrip `auth:generate`, tambahkan `README.md` root yang menunjuk ke `docs/README.md`.

### F-09 — Linimasa melabeli semua aktivitas sebagai "manual" · **Rendah**
- **Bukti:** `timeline.service.ts:112` memberi `source: "manual"` pada setiap item aktivitas; kueri SQL tidak memilih `activity_sessions.source`, padahal sesi impor bersumber `health_connect`.
- **Dampak:** provenans menyesatkan di UI/ekspor linimasa untuk sesi perangkat; bertentangan dengan prinsip "sumber selalu jujur".
- **Rekomendasi:** pilih dan teruskan `a.source` (dan `quality_status` sudah ada).

### F-10 — `requiredPermissions` pada kontrak alat hanya metadata · **Rendah**
- **Bukti:** `agent.tools.ts:23` dan `:105` — bidang itu dideklarasikan dan diekspos di `GET /api/me/agent/tools`, tetapi `executeTool` tidak memeriksanya. Consent diperiksa saat `createRun`/`decide`/`feedback`.
- **Dampak:** hari ini aman karena gerbang ada di atas, tetapi kontrak yang terlihat menjanjikan penegakan di tingkat alat; alat baru yang dipanggil dari jalur lain tidak otomatis dijaga.
- **Rekomendasi:** tegakkan di `executeTool` (pertahanan berlapis) atau hapus bidangnya dari kontrak.

### F-11 — Kebijakan keselamatan berbasis regex, belum ditinjau klinisi · **Sedang (diketahui)**
- **Bukti:** `agent.safety.ts` (`safety-policy-v1`); P3-08 `NOT_STARTED`; teks kebijakan consent bertanda draf. Regex tidak menangkap parafrase/ejaan lain/bahasa daerah; `explanationIsSafe` memblokir kata seperti "obat"/"dosis" secara harfiah.
- **Dampak:** tidak ada jaminan cakupan; kegagalan pada gejala darurat adalah kelas risiko tertinggi domain ini.
- **Rekomendasi:** tinjauan klinisi + korpus uji adversarial (parafrase, typo, campuran bahasa); pertimbangkan jalur "gejala = tampilkan pesan darurat statis" yang tidak bergantung pada intent.

### F-12 — Konfigurasi/skema yang tidak dipakai atau tidak selaras · **Rendah**
- Tujuan consent `product_analytics` terdaftar dan dapat diberikan/ditarik, tetapi tidak ada kode yang membaca atau mengirim data analitik.
- `user_settings_locale_valid` mengizinkan `en-US` di DB sedangkan API/Flutter hanya `id-ID`.
- `food_catalog.user_id` nullable ("katalog bersama") tetapi tidak ada kode yang membuat baris bersama; pencarian tetap menyertakannya.
- `.env.example` memuat `LLM_*` yang tidak dibaca (F-08).
- **Rekomendasi:** hapus atau dokumentasikan niatnya.

### F-13 — Cakupan populasi tidak konsisten antara blueprint dan kode · **Rendah**
- `ide.md` menyebut "prediabetes atau diabetes tipe 2 tahap pengelolaan dini"; `AGENTS.md` dan `computeEligibility` hanya "T2DM dewasa". `eligibility_status` dihitung dan disimpan, tetapi **tidak ada fitur yang bergantung padanya** (pengguna `needs_review` tetap mendapat semua fitur).
- **Rekomendasi:** putuskan populasi sasaran dan apakah `eligibility_status` harus membatasi sesuatu.

### F-14 — `CONSENT_REQUIRED` memakai status berbeda · **Rendah**
- `intervention.service.ts:132` melempar `conflict(409)`; semua modul lain (`consentService.requireConsent`) memakai `403`. Klien Flutter mengandalkan `code` sehingga belum bermasalah, tetapi klien lain/Bruno akan bingung.
- **Rekomendasi:** gunakan `consentService.requireConsent` atau `forbidden`.

### F-15 — Keandalan tes bergantung waktu dan keadaan bersama · **Rendah–Sedang**
- G-01 di `docs/audits/p3-readiness-audit.md` melaporkan kegagalan acak (429 saat suite diulang < 60 dtk; sensitif pada 23:00–23:59 UTC). Pada audit ini suite lulus penuh (dijalankan ±00:10 UTC pada stack baru), sehingga masalah tidak direproduksi.
- **Rekomendasi:** injeksi jam (`now()`) pada kode yang bergantung tanggal; naikkan batas laju atau nonaktifkan di stack uji; beri setiap berkas tes akun unik.

### F-16 — Tidak ada prosedur mendaftarkan model ke registri; DB prod tak punya baris model · **Sedang**
- **Bukti:** hanya `tests/integration/ml.test.ts` yang membuat `model_versions`; tidak ada skrip/migrasi/seed. Laporan P2 mencatat "prod needs same row".
- **Dampak:** tanpa baris itu `dishService.current()` null → fitur model mati (degradasi anggun, bukan galat), tetapi tidak ada cara terdokumentasi untuk mengaktifkannya; kredibilitas jejak persetujuan bergantung pada SQL manual.
- **Rekomendasi:** skrip `scripts/ml/register-model.ts` yang memvalidasi SHA/evaluasi dan menulis baris `RESEARCH_ONLY`; dokumentasikan alur Kaggle → Modal → registri → persetujuan (kerangkanya ada di [runbook §4.2](../operations/runbook.md)).

### F-17 — Pengamatan kecil (tidak direproduksi) · **Rendah/Info**
- `agent.service.ts:99` `emit()` menghitung `seq = count + 1` lalu `create`; dua `emit` bersamaan pada run yang sama dapat bentrok pada `UNIQUE(run_id, seq)` dan menjadi `500`. Run biasanya ditulis satu penulis, jadi sulit terjadi; belum direproduksi.
- SSE (`agent.stream.ts`) melakukan polling DB tiap 400 ms per koneksi dan memanggil `getRun` (beberapa kueri) pada setiap putaran; baik untuk satu pengguna, tidak berskala.
- `axllent/mailpit:latest` tidak dipin di compose dev/uji; `@types/bun: latest` (terkunci `bun.lock`).
- Koleksi Bruno tidak mencakup `scan/*`, push, agen, komunitas, ML, intervensi; cakupan hanya dari tes integrasi Bun.
- 365 berkas (±23 ribu baris) perubahan P0–P3 masih **staged tetapi belum di-commit** (HEAD `21daa31` "done"); risiko kehilangan pekerjaan. Sesuai aturan, hanya pengguna yang boleh meng-commit.

## 4. Kekuatan yang terverifikasi

| Area | Bukti |
|---|---|
| Kepemilikan data | seluruh query domain menyertakan `userId` dari sesi; ID klien tidak mengubah kepemilikan; rekaman orang lain → 404 |
| Idempotensi & konkurensi | `create_hash`, `UNIQUE(user, operation)`, `updateMany` ber-versi, penanganan `P2002`, `FOR UPDATE SKIP LOCKED` pada outbox |
| Kejujuran data | `NULL`≠0, `coverage`, `analyticsState`, penghitung porsi tanpa tebakan, `referenceCovers` menolak padanan semantik yang keliru |
| Keselamatan saran | penyaringan permintaan, validasi kandidat, filter alergi keras sebelum peringkat, gerbang teks LLM (tanpa angka baru/tautan), persetujuan tepat-sekali, rencana ≠ catatan |
| Privasi | consent per tujuan + versi, alias komunitas tanpa FK ke data kesehatan, kohort ≥ 5, foto tidak disimpan, push generik, `ml_inference_runs` tanpa gambar |
| Egress | host dipaku, `redirect: "error"`, batas ukuran/waktu, allowlist `*.modal.run`, URL hasil web disaring |
| Ketahanan | antrean offline per akun, kuitansi sinkronisasi, pemulihan run macet, dispatcher push idempoten, circuit breaker Modal |
| Hardening kontainer prod | `read_only`, `cap_drop: ALL`, `no-new-privileges`, jaringan DB internal, build bertahap, pengguna non-root |
| Disiplin repositori | tidak ada rahasia ter-track, `.env*` di-ignore, `src/generated` tidak ter-track, deny rule `git commit/push` di `.claude/settings.json` |

## 5. Prioritas tindakan yang disarankan

1. **Sebelum pengguna nyata:** F-01 (hapus akun/data) dan F-02 (ekspor lengkap) — keduanya menyangkut kewajiban privasi dan janji pada teks consent. Tinjauan hukum atas teks kebijakan (masih draf).
2. **Sebelum rilis Android:** F-03 (ID aplikasi, penandatanganan, `INTERNET`, Firebase, `API_BASE_URL`).
3. **Keandalan produk:** F-04 (siklus tantangan), F-16 (registri model), F-05 (batas laju bersama bila >1 replika).
4. **Kualitas proses:** F-06 (CI + pemindai rahasia), F-07 (bersihkan berkas stray), F-08 (perbarui `AGENTS.md`, README, skrip `auth:generate`), F-15 (stabilkan tes).
5. **Perbaikan kecil:** F-09, F-10, F-12, F-13, F-14, F-17.
6. **Risiko domain:** F-11 (tinjauan klinisi) sebelum menambah kapabilitas agen.

## 6. Batas audit

Audit ini adalah tinjauan statis + eksekusi tes otomatis. Ia **bukan** uji penetrasi, bukan penilaian klinis, bukan tinjauan hukum, dan tidak menilai kualitas visual UI. Klaim tentang perilaku di perangkat nyata, emulator, layanan pihak ketiga, dan produksi mengacu pada laporan proyek yang tidak diverifikasi ulang di sini.
