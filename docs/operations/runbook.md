# Runbook Operasional

> Diaudit 10 November 2026. Aturan keras proyek (dari `AGENTS.md`): **semua perintah server (build, migrasi, typecheck, tes, menjalankan API) dijalankan di dalam container Docker, bukan di host**; Flutter/Dart di `app/` dikecualikan (dijalankan di host); jangan meninggalkan berkas milik `root` di bind mount; jangan menulis kata sandi/token/secret sebagai literal di berkas ter-track; tidak ada `git commit/push` oleh agen.
> Perintah di bawah dijalankan dari **root repo** kecuali disebut lain. Prefiks `HOST_UID=$(id -u) HOST_GID=$(id -g)` mencegah berkas milik root (default compose 1000:1000).

## 1. Tiga stack

| Stack | Berkas | Isi | Data |
|---|---|---|---|
| Dev | `compose.yaml` (`name: beokay-dev`) | `postgres` (127.0.0.1:5433), `mailpit` (UI 127.0.0.1:8025), `api` (127.0.0.1:3000, `bun --hot`) | volume `pgdata` (persisten) |
| Uji | `compose.test.yaml` (`name: beokay-test`) | `postgres-test` (tmpfs), `mailpit-test`, `api-test`, `tester` (profil `tools`) | **dibuang** setelah `down -v`; tanpa port ke host |
| Prod | `compose.prod.yaml` (`name: beokay-prod`) | `postgres` → `migrate` (satu kali) → `api` | volume `pgdata`; jaringan `backend` internal |

Port host 5432/3000 dipakai proyek lain di mesin pemilik; beOkay memakai **5433** (DB) dan 3000 (API, dapat diubah via `API_HOST_PORT`).

### Dev
```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose up --build        # jalankan
docker compose up --build -V                                         # setelah dependensi berubah (reset volume node_modules)
docker compose exec api bun run typecheck                            # perintah satu kali
docker compose down        # stop (data tetap)   |   docker compose down -v   # hapus data DB
```
Saat start, container dev menjalankan `bun run db:generate && bun run db:migrate:deploy && bun --hot index.ts`. Email apa pun (verifikasi, reset) tertangkap di Mailpit `http://127.0.0.1:8025` dan tidak keluar ke internet. Dispatcher push **mati** di dev (`PUSH_DISPATCH_ENABLED_DEV`, default `false`).

### Uji
```bash
# seluruh suite (unit + integrasi) dengan DB terisolasi
docker compose -f compose.test.yaml run --rm --build tester
# API uji untuk Bruno/smoke
docker compose -f compose.test.yaml up -d --wait api-test
docker compose -f compose.test.yaml run --rm tester bun test tests/integration/glucose.test.ts   # satu berkas
docker compose -f compose.test.yaml down -v                          # bersihkan
```
**CI** (sejak 3.0 Fase 7, audit F-06): `.github/workflows/ci.yml` berjalan pada push ke `main`, pull request, dan manual. Tiga job: pemindaian rahasia (gitleaks v8.30.1 pada pohon kerja, konfigurasi `.gitleaks.toml`), backend (build image uji, `compose.test.yaml`, `bun run typecheck`, `bun test`, log API bila gagal, `down -v`), dan Flutter 3.44.4 (`pub get`, `analyze`, `test`). Workflow lolos `actionlint` 1.7.7 secara lokal; belum pernah berjalan di GitHub sampai pemilik mendorongnya.

Setelah mengubah dependensi: rebuild image **dan** `down -v` (volume `node_modules` hanya diisi saat pertama dibuat). `OUTBOX_WORKER_ENABLED=false` di stack uji; tes memanggil `outbox.drain()` sendiri agar deterministik.

**Hasil audit 10 Nov 2026:** `tsc --noEmit` tanpa galat; `bun test` → **238 lulus, 0 gagal, 1.705 `expect`, 48 berkas, 20,5 dtk**; `flutter analyze` bersih; `flutter test` → **157 lulus**.
**Peringatan keandalan (tercatat sebagai G-01 di `docs/audits/p3-readiness-audit.md`):** menjalankan suite berulang kali terhadap proses `api-test` yang sama dalam < 60 dtk dapat memicu `429` pada tes identitas (rate limit sign-up 5/menit di memori), dan sebagian tes dilaporkan sensitif terhadap tanggal UTC pada 23:00–23:59. Bila ada kegagalan acak, buat ulang `api-test` (`down -v` lalu jalankan lagi) sebelum menyelidiki.

### Prod
```bash
cp .env.prod.example .env.prod      # isi nilai WAJIB; JANGAN commit
docker compose -f compose.prod.yaml --env-file .env.prod up -d --build
```
Urutan: `postgres` sehat → `migrate` (one-shot, **harus sukses**) → `api`. API hanya di-bind ke loopback; **TLS/reverse proxy tidak termasuk** — taruh proxy di depannya dan pastikan ia **menimpa** `X-Forwarded-For` (bila tidak, set `TRUST_PROXY=false`, kalau tidak klien dapat memalsukan IP dan melewati rate limit). Kontainer API: `read_only`, `tmpfs /tmp`, `cap_drop: ALL`, `no-new-privileges`, batas memori 512 MB, log `json-file` 10 MB × 5. Jalankan **satu replika** (lihat §6).

## 2. Variabel lingkungan (`server/src/config/env.ts`)

Tidak valid → proses gagal start dengan `Invalid environment configuration: <bidang>`.

| Variabel | Wajib | Default | Fungsi / bila kosong |
|---|---|---|---|
| `NODE_ENV` | — | `development` | `development|test|production` |
| `PORT` | — | `3000` | |
| `DATABASE_URL` | **ya** | — | koneksi PostgreSQL |
| `BETTER_AUTH_SECRET` | **ya** | — | ≥ 32 karakter, unik per lingkungan |
| `BETTER_AUTH_URL` | **ya** | — | URL publik API (dipakai di tautan email) |
| `TRUSTED_ORIGINS` | — | kosong | CSV origin tambahan; kosong = hanya `BETTER_AUTH_URL` |
| `TRUST_PROXY` | — | `false` | prod default `true` di compose |
| `EMAIL_FROM`, `SMTP_HOST` | **ya** | — | pengirim & host SMTP |
| `SMTP_PORT` / `SMTP_SECURE` / `SMTP_USER` / `SMTP_PASS` | — | `587` / `false` / — / — | |
| `USDA_API_KEY` | — | — | kosong → pencarian USDA nonaktif (Open Food Facts tanpa kunci) |
| `MISTRAL_API_KEY` | — | — | kosong → OCR label, visi foto, embedding, dan penulis teks saran nonaktif |
| `MISTRAL_VISION_MODEL` / `MISTRAL_OCR_MODEL` / `MISTRAL_EMBEDDING_MODEL` / `MISTRAL_AGENT_MODEL` | — | `mistral-small-latest` / `mistral-ocr-latest` / `mistral-embed` / `mistral-small-latest` | host dipaku `api.mistral.ai` di kode |
| `TAVILY_API_KEY` | — | — | kosong → pencarian web penemuan makanan nonaktif |
| `FIRECRAWL_API_KEY` | opsional | tombol "Cari di web" pada draf catatan makan (Firecrawl `v2/search`); tanpa kunci membalas `NOT_CONFIGURED`. Nama makanan dikirim hanya atas permintaan pengguna |
| `FCM_PROJECT_ID` + `FCM_SERVICE_ACCOUNT_JSON` | — | — | keduanya perlu; JSON mentah **atau base64** (`base64 -w0 file.json`). Kosong → push nonaktif, pengingat tetap lokal |
| `PUSH_DISPATCH_ENABLED` | — | `true` | dev compose: `false` |
| `OUTBOX_WORKER_ENABLED` | — | `true` | `false` di stack uji |
| `NOTIFY_WORKER_ENABLED` | — | `true` | pekerja notifikasi (pengingat tiap 30 dtk, ajakan refleksi tiap jam); `false` di stack uji |
| `CHALLENGE_LIFECYCLE_ENABLED` | — | `true` | siklus tantangan (buat/buka/tutup/hasil tiap jam + penyegaran malas); `false` di stack uji, tes memanggil `runChallengeLifecycle(now)` langsung |
| `MODAL_ML_URL` + `MODAL_ML_AUTH_TOKEN` | — | — | harus `https://*.modal.run`; kosong → inferensi model nonaktif |
| `UPLOADTHING_TOKEN` | — | — | hanya skrip operasional |
| `METRICS_TOKEN` *(Fase 9)* | prod: **ya** | — | Bearer untuk `GET /metrics`; tanpa token endpoint `404` di `production` |
| `ALERT_EMAIL_TO` *(Fase 9)* | — | — | surel tujuan `check-alarms.ts` |
| `PUBLIC_BASE_URL` *(Fase 9)* | — | `BETTER_AUTH_URL` | dasar URL tautan baca-saja `/s/<token>` |
| `FEATURES_DISABLED` *(Fase 8)* | — | kosong | CSV kunci fitur yang mati bila tidak ada baris di `feature_flags`: `assistant`, `conversation`, `coaching`, `community`, `ml_inference`, `food_vision`, `web_discovery`, `analytics`, `push` |
| `FEATURE_FLAG_CACHE_MS` *(Fase 8)* | — | `30000` | umur cache sakelar fitur; stack uji `0` |
| `INCIDENT_EMAIL_TO` *(Fase 8)* | — | — | surel pemilik untuk laporan masalah/kejadian; kosong → laporan tetap tersimpan di DB, log `incident_email_not_configured` |
| `RETENTION_WORKER_ENABLED` *(Fase 8)* | — | `true` | pekerja retensi harian; `false` di stack uji |
| `RETENTION_AGENT_EVENTS_DAYS` / `RETENTION_READ_NOTIFICATIONS_DAYS` / `RETENTION_AUDIT_DAYS` / `RETENTION_USAGE_DAYS` / `RETENTION_OUTBOX_DAYS` | — | `90` / `60` / `365` / `400` / `30` | batas umur data yang dihapus pekerja retensi |

Variabel compose/host: `HOST_UID`, `HOST_GID`, `POSTGRES_USER/PASSWORD/DB`, `POSTGRES_HOST_PORT` (5433), `API_HOST_PORT` (3000), `MAILPIT_UI_PORT` (8025), `APP_VERSION` (prod).
**Catatan:** blok `LLM_*` di `.env.example` **tidak dibaca kode mana pun** (hanya `MISTRAL_*` yang dipakai); komentarnya ("belum dipakai kode P0/P1") sudah usang (audit F-08).

Rahasia hanya di `.env*` (gitignored) atau secret manager. Hanya `*.example` yang boleh ter-track. Dev compose memiliki default `BETTER_AUTH_SECRET` publik (`dev-only-…`) — **jangan dipakai di luar dev**.

## 3. Migrasi basis data

Skrip `db:*` wajib dipakai (bukan `bunx prisma …`: `bunx`/`bun run prisma` tidak memuat `.env` untuk `prisma.config.ts`).
```bash
docker compose exec api bun run db:generate          # Prisma Client → src/generated (jangan di-commit/diedit)
docker compose exec api bun run db:migrate:deploy    # terapkan migrasi
docker compose exec api bun run db:studio
```
**Membuat migrasi baru** (agar CHECK/indeks parsial/trigger bisa ditulis): menurut `AGENTS.md`, jalankan `bun run db:migrate:dev -- --create-only --name <nama>` **di container uji dengan DB kosong**. Perhatikan: service `tester` bergantung pada `api-test` yang sudah menerapkan semua migrasi, jadi DB-nya tidak kosong; siapkan DB uji baru (mis. `down -v` lalu jalankan hanya `postgres-test` dan kontainer sekali-pakai tanpa `api-test`). Urutan persis ini tidak terdokumentasi di repo dan **tidak diuji pada audit ini**. Setelah berkas dibuat, tambahkan SQL `CHECK`/indeks parsial/trigger secara manual, terapkan, dan verifikasi `bun run db:migrate:diff`. Selisih yang diizinkan: default `gen_random_uuid` pada 4 tabel auth, indeks HNSW `food_reference_embedding_idx`, serta objek khusus-SQL yang diketahui (G-02). Menambah tujuan **consent** baru = ubah `consent.policy.ts` **dan** migrasi yang mendrop/membuat ulang `consent_records_purpose_valid`.

Model auth dihasilkan CLI: ubah `src/features/auth/auth.ts` lalu regenerasi — **namun skrip `auth:generate` di `package.json` menunjuk `src/lib/auth.ts` yang tidak ada**; perbaiki jalurnya sebelum dipakai, dan tambahkan kembali relasi balik di model `Users` bila tertimpa.

## 4. Pipeline data dan model

### 4.1 Referensi gizi TKPI (`server/scripts/tkpi/`)
OCR PDF TKPI (Mistral OCR, potongan 20 halaman) → `parse.ts` → `ingest.ts` (isi `food_reference` + embedding `mistral-embed`, status `verified_auto` bila lolos validasi Atwater + jumlah proksimat) → `upload.ts` (arsip PDF ke UploadThing). Berkas OCR/parsed **tidak disimpan di repo**:
```bash
docker compose -f compose.test.yaml run --rm -v <folder>:/data:ro tester bun run scripts/tkpi/ingest.ts /data/parsed.json
```
Kunci (`MISTRAL_API_KEY`, `UPLOADTHING_TOKEN`) hanya dari env. Menurut catatan P1, hasil: 1.132 baris terurai, 1.037 `verified_auto`; cakupan makanan olahan rendah (mis. "nasi goreng", "lontong", "sambal" tidak ada). Jumlah baris di DB pada audit ini tidak diperiksa.

### 4.2 Model pengenal hidangan (`ml/`)
1. **Latih** di Kaggle: `ml/kaggle/train.py` + `kernel-metadata.json` (kernel `misbahulmuttaqin/beokay-dish-classifier`, GPU, dataset `rizkyyk/dataset-food-classification`, 13 kelas). Keluaran: `model.pt`, `classes.json`, `metrics.json`, `report.md`, `split_audit.json`. Audit kebocoran (hash berkas + dHash) wajib; angka yang dilaporkan adalah akurasi **tanpa duplikat** (0,955), bukan 0,969.
2. **Deploy** ke Modal: `ml/modal_app.py` (app `beokay-dish-classifier`; Volume `beokay-models` berisi `/dish/<versi>/{model.pt,classes.json}` dan `current.json` dengan SHA-256 yang diverifikasi saat memuat; Secret `beokay-ml-auth` → `ML_AUTH_TOKEN`, dibandingkan waktu-konstan).
3. **Daftarkan** versi (sejak 3.0 Fase 7, menutup audit F-16). Unduh keluaran kernel Kaggle (`model.pt`, `metrics.json`, `classes.json`) ke satu folder di luar repo, lalu:
   ```bash
   docker compose run --rm -v ~/kaggle-out/v2:/data:ro api bun run scripts/ml/register-model.ts dish-classifier v2-20261120 /data --expect-sha <sha256 dari current.json Modal> --dry-run
   docker compose run --rm -v ~/kaggle-out/v2:/data:ro api bun run scripts/ml/register-model.ts dish-classifier v2-20261120 /data --expect-sha <sha256 dari current.json Modal>
   ```
   Prod: ganti `docker compose` dengan `docker compose -f compose.prod.yaml --env-file .env.prod` dan service `migrate` (image yang punya `scripts/`). Skrip menghitung SHA-256 `model.pt` sendiri, mengambil `intended_use`, `training_data_provenance`, `feature_schema_version`, dan `endpoint_ref` dari kartu model `server/scripts/ml/model-cards/<modelKey>.json`, meringkas `metrics.json` (uji penuh, uji tanpa duplikat, audit kebocoran, batasan; tanpa matriks per kelas), lalu menulis baris **`RESEARCH_ONLY`**. Ditolak bila: SHA tidak sama dengan `--expect-sha`, tidak ada uji tanpa duplikat atau audit kebocoran, `classes.json` berbeda dari `metrics.json`, atau versi yang sama sudah terdaftar dengan artefak lain. Menjalankan ulang dengan artefak yang sama aman (`UNCHANGED`). Logika di `src/features/ml/model-registry.ts`; tes `tests/unit/model-registry.test.ts` dan `tests/integration/model-registry.test.ts`.
4. **Ubah status** (pemilik, di container): `docker compose run --rm api bun run scripts/ml/set-model-status.ts <modelKey> <versi> <RESEARCH_ONLY|SHADOW|APPROVED|DEPRECATED> "<catatan>"`. `APPROVED` ditolak bila akurasi uji tanpa duplikat < 0,90 atau catatan < 20 karakter.
Status model saat dilaporkan: `RESEARCH_ONLY` (lisensi dataset tidak tercantum); di DB **dev** sempat dinaikkan ke `APPROVED` untuk uji. Jangan mengklaim akurasi pada foto pengguna nyata — tidak pernah diukur.

## 5. Pemeliharaan dan pemantauan

- **Kesehatan**: `GET /health` (200/503) dipakai healthcheck compose.
- **Metrik** (sejak 3.0 Fase 9): `GET /metrics` (Prometheus, `Authorization: Bearer $METRICS_TOKEN`). Penghitung ada di memori proses dan mulai dari nol setiap restart. SLO pilot: p95 < 800 ms, `beokay_outbox_events{status="DEAD"}` = 0, push gagal < 5% dalam 24 jam.
- **Alarm** (sejak 3.0 Fase 9): `docker compose -f compose.prod.yaml --env-file .env.prod run --rm api bun run scripts/ops/check-alarms.ts --api=http://api:3000` memeriksa SLO di atas dan laporan kejadian yang belum terkirim, mencetak JSON, keluar dengan kode 1 bila ada masalah, dan mengirim surel ke `ALERT_EMAIL_TO`. Contoh cron tiap 15 menit di host: `*/15 * * * * cd /srv/beokay && docker compose -f compose.prod.yaml --env-file .env.prod run --rm -T api bun run scripts/ops/check-alarms.ts --api=http://api:3000 >> ~/beokay-alarms.log 2>&1`. `--dry-run` tidak mengirim surel.
- **Reverse proxy**: contoh konfigurasi Caddy dan nginx dengan HSTS, batas badan, dan penerusan WebSocket di [reverse-proxy.md](reverse-proxy.md).
- **Log**: satu baris JSON per permintaan (`requestId`, `method`, `path`, `status`, `durationMs`, `userId`); tidak memuat badan/isi kesehatan. Peristiwa khas: `push_status`, `push_dispatch`, `outbox_drained`, `outbox_event_failed`, `outcomes_swept`, `ml_shadow_failed`, `food_scan_label`, `challenge_lifecycle` / `challenge_lifecycle_failed`, `notification_push_failed`, `notification_worker_failed`.
- **Realtime**: WebSocket `/api/me/realtime` dilayani proses API yang sama (Bun). Bila API diletakkan di belakang reverse proxy, proxy harus meneruskan `Upgrade`/`Connection` dan memberi idle timeout > 120 dtk; tanpa itu aplikasi tetap bekerja (kotak masuk dimuat lewat HTTP) tetapi tanpa pembaruan langsung. Langganan hanya di memori proses, sejalan dengan batas satu replika di bawah.
- **Outbox**: antrean macet bila `outbox_events.status='DEAD'` bertambah; `outbox.stats()` mengelompokkan per status (tidak ada endpoint). Pekerja menguras tiap 3 dtk, menyapu hasil terukur tiap 60 dtk.
- **Retensi data** (sejak 3.0 Fase 8, `retention-v1`): pekerja harian menghapus `agent_run_events` > 90 hari, notifikasi yang **sudah dibaca** > 60 hari, `audit_events` > 365 hari, `usage_events` > 400 hari, dan `outbox_events` `DONE` > 30 hari (semua bisa diubah lewat env). Notifikasi belum dibaca, catatan kesehatan, dan revisi tidak pernah dihapus pekerja ini. Setiap putaran mencatat `audit_events` `retention_applied` dengan jumlah per tabel. Uji kering: `docker compose -f compose.prod.yaml --env-file .env.prod run --rm api bun run scripts/ops/retention.ts` (tambahkan `--apply` untuk menghapus).
- **Sakelar fitur** (sejak 3.0 Fase 8): `docker compose ... run --rm api bun run scripts/ops/feature-flag.ts set community off --by <nama> --note "<alasan>"` mematikan fitur dalam ≤ 30 dtk tanpa restart (`list`, `clear <kunci> --by <nama>`). Rute fitur yang mati membalas `503 FEATURE_DISABLED`; aplikasi menampilkan "Fitur ini dimatikan sementara". Setiap perubahan tercatat `feature_flag_changed` (siapa, dari, ke, catatan).
- **Router hibrida** (sejak 3.0 Fase 10): matikan dengan `feature-flag.ts set llm_router off`. Pantau `router_proposals` (`SELECT decision, reject_reason, count(*) FROM router_proposals WHERE created_at > now() - interval '7 days' GROUP BY 1,2`) dan log `beokay_log_events_total`. Mengubah prompt atau model wajib menjalankan ulang `router-eval.ts` dan mencatat hasilnya di laporan fase.
- **Modul edukasi** (sejak 3.0 Fase 11): isi di `server/src/content/education/modules.ts`, disinkronkan otomatis saat API mulai (log `education_synced`). Produksi hanya menampilkan versi `REVIEWED` (`EDUCATION_INCLUDE_DRAFTS=false`). Setelah klinisi menyetujui: `docker compose ... run --rm api bun run scripts/ops/education.ts review <key> <versi> "<nama peninjau>"`; `list` menampilkan status dan hash isi, `retire <key> <versi>` menarik modul. Mengubah isi modul yang sudah ditinjau wajib menaikkan `version` (sinkron menolak dan mencatat `education_content_changed_without_version`).
- **Hidangan terkurasi** (sejak 3.0 Fase 11): `docker compose ... run --rm api bun run scripts/food/curate-dishes.ts` menghitung ulang 45 hidangan dari bahan TKPI di DB (idempoten; `--no-embed` tanpa embedding). Jalankan setelah ingest TKPI. Ukur cakupan pencarian dengan `scripts/food/search-hit-rate.ts`.
- **Moderasi komunitas** (sejak 3.0 Fase 11): `docker compose ... run --rm api bun run scripts/ops/community-reports.ts list` menampilkan antrean laporan terbuka; `uphold <membershipId> "<catatan>"` menahan alias tetap tersembunyi dan memberi tahu pemiliknya untuk mengganti alias, `dismiss <membershipId>` memulihkan. Periksa antrean setidaknya mingguan selama pilot.
- **CGM dan pendamping** (sejak 3.0 Fase 11): matikan dengan `feature-flag.ts set cgm off` / `set companion off`. Halaman `/c/:token` di-cache `no-store` dan tidak diindeks.
- **Laporan masalah/kejadian** (sejak 3.0 Fase 8): `incident_reports` + surel ke `INCIDENT_EMAIL_TO`. Laporan berkategori `adverse_event` harus dibaca dalam 1 hari kerja selama pilot (protokol pilot §keselamatan). Laporan tetap tersimpan bila surel gagal (`emailed_at` kosong); cek dengan `SELECT id, category, created_at FROM incident_reports WHERE emailed_at IS NULL`.
- **Ukuran keberhasilan** (sejak 3.0 Fase 8): `docker compose ... run --rm api bun run scripts/analytics/measures.ts --days 28` menghitung semua ukuran Fase 8 dari DB untuk kohort ber-consent `product_analytics` (lihat [measures.md](../research/measures.md)).
- **Cadangan/pemulihan** (sejak 3.0 Fase 7): `scripts/ops/db-backup.sh` menjalankan `pg_dump --format=custom` di dalam container Postgres, memvalidasi arsip dengan `pg_restore --list`, menyimpannya di `~/beokay-backups` (izin 700/600) bersama `.sha256`, dan menyimpan 14 terbaru (`BEOKAY_BACKUP_KEEP`). `scripts/ops/db-restore.sh <berkas> --yes` memeriksa checksum lalu `pg_restore --clean --if-exists`; hentikan `api` dulu. Diuji pulang-pergi pada stack uji: baris sintetis dan ekstensi `vector`/`pg_trgm` pulih, checksum rusak ditolak, tanpa `--yes` ditolak.
  ```bash
  scripts/ops/db-backup.sh -f compose.prod.yaml --env-file .env.prod
  docker compose -f compose.prod.yaml --env-file .env.prod stop api
  scripts/ops/db-restore.sh ~/beokay-backups/beokay-<UTC>.dump --yes -f compose.prod.yaml --env-file .env.prod
  ```
  Penjadwalan belum dipasang. Contoh cron harian di host: `15 2 * * * cd /srv/beokay && scripts/ops/db-backup.sh -f compose.prod.yaml --env-file .env.prod >> ~/beokay-backups/backup.log 2>&1`. Salin cadangan ke lokasi lain (di luar mesin yang sama) dan uji pemulihan berkala; cadangan berisi data kesehatan, jadi simpan terenkripsi.
- **Pergantian akun/perangkat**: token push milik akun terakhir yang mendaftarkannya.

- **Deploy serverless** (sejak 12 Nov 2026): Vercel + Neon, pekerja diganti `/internal/jobs/tick`; lihat [deploy-vercel-neon.md](deploy-vercel-neon.md).

## 6. Batas operasional yang harus diketahui

1. **Satu replika API.** Pembatas laju, cache, dan circuit breaker di memori proses (lihat [system-overview §9](../architecture/system-overview.md)).
2. **Tantangan komunitas diperbarui otomatis** sejak 3.0 Fase 6 (`challenge-lifecycle-v1`): dua templat (`weekly-active-3`, `four-week-active-12`) membuat periode berjalan dan berikutnya untuk tiap komunitas, berdasarkan tanggal di `Asia/Jakarta`. Tantangan seed lama (tanpa templat) tetap ada dan ditutup saat jendelanya lewat. Menambah templat cukup dengan baris baru di `challenge_templates` (lewat migrasi). Siklus berjalan per proses; menjalankannya di beberapa replika aman (langkah bersyarat status) tetapi boros.
3. **Push nyata terblokir** sampai aplikasi didaftarkan di Firebase dengan `applicationId` asli dan `google-services.json` ditempatkan di `app/android/app/`; kredensial server harus dari proyek yang sama. Server sudah membuat notifikasi, menyimpannya di kotak masuk, dan mengirimnya lewat WebSocket tanpa Firebase; FCM hanya menambah push saat aplikasi tertutup. Pengaturan notifikasi di aplikasi menampilkan "Belum ada perangkat terdaftar untuk push" selama perangkat belum mendaftarkan token.
4. **Rilis Android** (sejak 10 Nov 2026): `applicationId`/namespace `id.beokay.app`; izin `INTERNET` di manifes utama. Build rilis **ditolak Gradle** bila `app/android/key.properties` tidak ada atau `API_BASE_URL` bukan `https://`. Buat kunci sekali dan simpan di luar repo:
   ```bash
   keytool -genkeypair -keystore ~/beokay-release.jks -alias beokay -keyalg RSA -keysize 2048 -validity 10000
   # app/android/key.properties (gitignored): storeFile=/home/<user>/beokay-release.jks, storePassword=…, keyAlias=beokay, keyPassword=…
   cd app && flutter build appbundle --release --dart-define=API_BASE_URL=https://api.domain-anda
   ```
   Kehilangan kunci ini berarti aplikasi di Play Store tidak bisa diperbarui; cadangkan. Push masih butuh pendaftaran `id.beokay.app` di Firebase + `google-services.json`.
5. **Penghapusan akun/data** tersedia untuk pengguna (Pengaturan → Privasi & data → Hapus akun; `POST /api/me/account/delete` dengan kata sandi + `confirm: "HAPUS"`). Semua tabel ber-`user_id` terhapus lewat cascade (diuji per tabel); `audit_events` dan `ml_inference_runs` dianonimkan (`user_id = NULL`). Rute bawaan Better Auth `/api/auth/delete-user` diblokir karena mengizinkan hapus tanpa kata sandi.

## 7. Skrip pendukung

| Skrip | Fungsi |
|---|---|
| `server/scripts/tkpi/{parse,ingest,upload}.ts` | pipeline TKPI |
| `server/scripts/ml/register-model.ts` + `model-cards/` | mendaftarkan versi model dari artefak pelatihan sebagai `RESEARCH_ONLY` |
| `server/scripts/ml/set-model-status.ts` | tata kelola status model |
| `scripts/ops/db-backup.sh`, `scripts/ops/db-restore.sh` | cadangan dan pemulihan Postgres (dijalankan di host, perintah DB di dalam container) |
| `server/scripts/eval/router-eval.ts` | evaluasi router hibrida dengan model sungguhan: penurunan UNKNOWN di korpus dan set terpisah, rute salah, pelanggaran gerbang pada 100 kalimat injeksi (butuh `MISTRAL_API_KEY`) |
| `server/scripts/ops/check-alarms.ts` | alarm SLO (latensi dari `/metrics`, outbox, push, laporan kejadian) |
| `server/scripts/ops/feature-flag.ts` | sakelar fitur tanpa restart (`list`, `set <kunci> on|off --by`, `clear`) |
| `server/scripts/ops/retention.ts` | retensi data (uji kering bawaan, `--apply` untuk menghapus) |
| `server/scripts/ops/education.ts` | status dan tinjauan modul edukasi (`list`, `sync`, `review`, `retire`) |
| `server/scripts/ops/community-reports.ts` | antrean laporan alias komunitas (`list`, `uphold`, `dismiss`) |
| `server/scripts/food/curate-dishes.ts`, `server/scripts/food/search-hit-rate.ts` | hidangan terkurasi dari TKPI dan pengukuran hit rate 20 kueri teratas |
| `server/scripts/analytics/measures.ts` | ukuran keberhasilan Fase 8 dari DB (`--days`, `--from`, `--to`) |
| `docs/api/bruno/` | koleksi Bruno (modul 08–19), environment `test` |

Skrip sementara **jangan** ditaruh di dalam repo (pakai scratchpad atau hapus sebelum selesai) — insiden GitGuardian 8 Nov 2026 (`d9a8749`) berasal dari kata sandi akun sintetis di skrip uji sementara (bukan rahasia asli).
