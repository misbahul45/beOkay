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
| `BRAVE_API_KEY` | — | — | kosong → pencarian web nonaktif |
| `FIRECRAWL_API_KEY` | opsional | tombol "Cari di web" pada draf catatan makan (Firecrawl `v2/search`); tanpa kunci membalas `NOT_CONFIGURED`. Nama makanan dikirim hanya atas permintaan pengguna |
| `FCM_PROJECT_ID` + `FCM_SERVICE_ACCOUNT_JSON` | — | — | keduanya perlu; JSON mentah **atau base64** (`base64 -w0 file.json`). Kosong → push nonaktif, pengingat tetap lokal |
| `PUSH_DISPATCH_ENABLED` | — | `true` | dev compose: `false` |
| `OUTBOX_WORKER_ENABLED` | — | `true` | `false` di stack uji |
| `MODAL_ML_URL` + `MODAL_ML_AUTH_TOKEN` | — | — | harus `https://*.modal.run`; kosong → inferensi model nonaktif |
| `UPLOADTHING_TOKEN` | — | — | hanya skrip operasional |

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
3. **Daftarkan** versi di tabel `model_versions` (`artifact_sha256`, `feature_schema_version`, `evaluation`, `endpoint_ref`, …). **Belum ada skrip atau migrasi untuk ini** — baris di DB dev dimasukkan manual dan hanya tes (`tests/integration/ml.test.ts`) yang membuatnya lewat kode. DB produksi **tidak memiliki** baris itu (audit F-16).
4. **Ubah status** (pemilik, di container): `docker compose run --rm api bun run scripts/ml/set-model-status.ts <modelKey> <versi> <RESEARCH_ONLY|SHADOW|APPROVED|DEPRECATED> "<catatan>"`. `APPROVED` ditolak bila akurasi uji tanpa duplikat < 0,90 atau catatan < 20 karakter.
Status model saat dilaporkan: `RESEARCH_ONLY` (lisensi dataset tidak tercantum); di DB **dev** sempat dinaikkan ke `APPROVED` untuk uji. Jangan mengklaim akurasi pada foto pengguna nyata — tidak pernah diukur.

## 5. Pemeliharaan dan pemantauan

- **Kesehatan**: `GET /health` (200/503) dipakai healthcheck compose. Tidak ada metrik, pelacakan, atau alarm agregat.
- **Log**: satu baris JSON per permintaan (`requestId`, `method`, `path`, `status`, `durationMs`, `userId`); tidak memuat badan/isi kesehatan. Peristiwa khas: `push_status`, `push_dispatch`, `outbox_drained`, `outbox_event_failed`, `outcomes_swept`, `ml_shadow_failed`, `food_scan_label`.
- **Outbox**: antrean macet bila `outbox_events.status='DEAD'` bertambah; `outbox.stats()` mengelompokkan per status (tidak ada endpoint). Pekerja menguras tiap 3 dtk, menyapu hasil terukur tiap 60 dtk.
- **Data lama**: tidak ada kebijakan retensi terjadwal; `audit_events` dan `agent_run_events` tumbuh tanpa batas (hanya ekspor yang membatasi 5.000 audit).
- **Cadangan/pemulihan**: tidak ada prosedur atau otomasi di repo — `pgdata` adalah satu-satunya salinan. Siapkan `pg_dump` terjadwal sebelum pengguna nyata.
- **Pergantian akun/perangkat**: token push milik akun terakhir yang mendaftarkannya.

## 6. Batas operasional yang harus diketahui

1. **Satu replika API.** Pembatas laju, cache, dan circuit breaker di memori proses (lihat [system-overview §9](../architecture/system-overview.md)).
2. **Tantangan komunitas tidak diperbarui otomatis.** Satu tantangan per komunitas di-seed oleh migrasi dengan jendela `CURRENT_DATE … +27 hari`; setelah itu `CHALLENGE_CLOSED` dan tidak ada jalur untuk membuat yang baru (audit F-04). Pada DB prod baru, jendela dimulai pada hari migrasi dijalankan.
3. **Push nyata terblokir** sampai aplikasi didaftarkan di Firebase dengan `applicationId` asli dan `google-services.json` ditempatkan di `app/android/app/`; kredensial server harus dari proyek yang sama.
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
| `server/scripts/ml/set-model-status.ts` | tata kelola status model |
| `docs/api/bruno/` | koleksi Bruno (modul 08–19), environment `test` |

Skrip sementara **jangan** ditaruh di dalam repo (pakai scratchpad atau hapus sebelum selesai) — insiden GitGuardian 8 Nov 2026 (`d9a8749`) berasal dari kata sandi akun sintetis di skrip uji sementara (bukan rahasia asli).
