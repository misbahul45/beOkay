# beOkay — Agent Instructions

Personal Metabolic Performance Platform (T2DM, adult, personal). Mobile client + modular API + PostgreSQL.
Sumber spesifikasi: *Database & UI/UX Master Blueprint v0.1* (proposed design, bukan skema final).

## ATURAN KERAS — GIT
- **JANGAN PERNAH `git commit`, `git push`, atau membuat commit/PR lewat tool apa pun** (termasuk `gh`, GitHub MCP `push_files`, `create_or_update_file`, `merge_pull_request`).
- Jangan `git init`, `git tag`, `git stash`, atau mengubah remote tanpa diminta eksplisit.
- Selesai mengubah file = berhenti. Pengguna sendiri yang melakukan commit/push.
- Aturan ini juga ditegakkan di `.claude/settings.json` (deny). Jangan menghapus atau melonggarkannya.

## Struktur
- `server/` — Bun + TypeScript API. ORM: **Prisma 7** (driver adapter `@prisma/adapter-pg`). Ikuti `server/CLAUDE.md` (Bun-first) **kecuali** untuk database: pakai Prisma, bukan `Bun.sql` (keputusan pengguna).
- `server/src/` — **feature-based**: `features/{auth,consent,onboarding,profile,health-profile,preferences}/` (masing-masing: routes, service, repository, schema Zod), `shared/` (error, HTTP wrapper, audit), `infrastructure/` (database, email), `config/env.ts`. Modul tidak boleh saling bergantung melingkar.
- `app/` — Flutter (scaffold bawaan, belum dikerjakan).
- `design/` — desain FigCraft + token Dart. `docs/` — audit, arsitektur, database, API.
- `compose.yaml` (dev), `compose.test.yaml` (uji terisolasi), `compose.prod.yaml` (prod), `.env.example`, `.env.prod.example`.

## Cakupan saat ini (jangan melebar)
- Sudah: koneksi DB + Prisma + `/health`; stack Docker dev, uji, prod; **Better Auth** dengan verifikasi email wajib, reset kata sandi, rate limit, plugin `bearer` (sesi mobile), email via SMTP (Mailpit di dev); tabel domain identitas `user_profiles`, `health_profiles`, `user_settings`, `consent_records`, `onboarding_progress`, `audit_events`; API `/api/me/*` dan `/api/consent-policies/current`.
- **Belum, dan jangan dibuat tanpa diminta**: tabel/modul domain pencatatan (meal, glucose, activity, medication, dst.), UI Flutter, ringkasan/insight.
  Skema P0 penuh masih menunggu: Data Dictionary, Physical ERD, Screen Specification, UI–API Contract Matrix.
- Desain UI dikerjakan di Figma (figcraft) lebih dulu, baru implementasi.

## ATURAN KERAS — EKSEKUSI LEWAT DOCKER
- **Semua perintah build, migrasi, typecheck, test, dan menjalankan API dilakukan di dalam container Docker, bukan di host.** Pakai `docker compose run --rm` / `docker compose exec`. Jangan menjalankan `bun`, `prisma`, `bun test`, atau `bun index.ts` langsung di host.
- Perkecualian: alat GUI/desain (FigCraft), git, dan **Flutter/Dart (`app/`) yang dijalankan di host** (keputusan pengguna: tidak memakai image Flutter).
- Container tidak boleh meninggalkan file milik `root` di bind mount (`./server`, `./app`). Jalankan dengan `--user "$(id -u):$(id -g)"` atau atur `user:` di compose.
- Pengujian memakai database terisolasi (service/DB terpisah dari data dev), bukan DB dev.

## ATURAN KERAS — KREDENSIAL
- Jangan menulis kata sandi, token, atau secret sebagai literal di berkas yang di-track (kode, tes, skrip, Bruno). Tes dan skrip membangkitkannya saat dijalankan (acak per eksekusi) atau membacanya dari env.
- Nilai placeholder dev hanya boleh ada di `*.example`. Skrip sementara jangan ditaruh di dalam repo; pakai scratchpad, atau hapus sebelum selesai.
- Insiden GitGuardian 8 Nov 2026 (`d9a8749`): kata sandi akun sintetis di skrip uji sementara. Bukan rahasia asli (akun hanya ada di DB uji yang dimusnahkan); tidak perlu rotasi.

## Perintah (di dalam container; path relatif terhadap `server/`)
- Dev stack (root): `docker compose up --build` — API `127.0.0.1:3000`, Postgres `127.0.0.1:5433`, Mailpit UI `127.0.0.1:8025`. Container dev menjalankan `db:generate` dan `db:migrate:deploy` saat start.
- Perintah satu kali di dev: `docker compose exec api bun run typecheck` (atau `docker compose run --rm api ...`).
- Stack uji terisolasi (root): `docker compose -f compose.test.yaml up -d --wait api-test`, lalu `docker compose -f compose.test.yaml run --rm tester bun test`; bersihkan dengan `docker compose -f compose.test.yaml down -v`. Setelah mengubah dependensi, rebuild image dan hapus volume `node_modules` (`down -v`), karena Docker hanya mengisi volume saat pertama dibuat.
- Membuat migrasi baru: jalankan `bun run db:migrate:dev -- --create-only --name <nama>` di container uji (DB kosong), lalu tambahkan CHECK/partial index lewat SQL dan verifikasi `prisma migrate diff` (hanya noise `gen_random_uuid` pada 4 tabel auth dan indeks HNSW `food_reference_embedding_idx` yang boleh tersisa; HNSW pgvector tidak dapat diekspresikan di skema Prisma).
- Prod stack (root): `docker compose -f compose.prod.yaml --env-file .env.prod up -d --build` (wajib: password DB, `BETTER_AUTH_*`, `EMAIL_FROM`, `SMTP_HOST`).
- `bun run typecheck` · `bun run db:generate` · `bun run db:migrate:dev` · `bun run db:migrate:deploy` · `bun run db:studio`.
- **Pakai script `db:*`, bukan `bunx prisma ...`**: `bunx`/`bun run prisma` tidak memuat `.env` untuk `prisma.config.ts` (DATABASE_URL tidak ter-resolve). Script memanggil `bun --bun ./node_modules/.bin/prisma`.

## Deploy serverless (Vercel + Neon)
- API produksi: proyek Vercel `beokay-api` (Root Directory = `server`, `server/vercel.json`, preset Bun, tersambung ke GitHub `main`), URL `https://beokay-api.vercel.app`. Deploy CLI dari **root repo** (`vercel deploy --prod`), bukan dari `server/`. DB: proyek Neon `beokay`. Panduan: `docs/operations/deploy-vercel-neon.md`.
- Rahasia deploy ada di `/.env.deploy` (gitignored). **Jangan `source` berkas itu** (URL Neon memuat `&`); baca dengan pengurai kutip.
- Pekerja latar di Vercel dimatikan; job berjalan lewat `/internal/jobs/tick` (`CRON_SECRET`). Tugas setelah respons memakai `background()` (`waitUntil`).

## Konvensi data (dari blueprint, berlaku saat skema dibuat)
- PK `UUID`, waktu `TIMESTAMPTZ`, ukuran `NUMERIC`, `JSONB` hanya untuk metadata variabel.
- Nilai tidak diketahui = `NULL`, bukan `0`. Prediksi tidak disimpan di tabel pengukuran.
- Semua query dibatasi kepemilikan `user_id`. Koreksi data lewat `record_revisions`.
- Auth = Better Auth (keputusan pengguna). Model auth di `prisma/schema.prisma` dihasilkan CLI: ubah `src/features/auth/auth.ts` lalu `bun run auth:generate` (di container), bukan edit manual. Pengecualian: baris relasi balik ke tabel domain di model `Users` ditambahkan manual; tambahkan lagi bila `auth:generate` menimpanya. Jangan buat mekanisme password sendiri. Nama tampilan = `users.name` (satu sumber), diubah lewat `auth.api.updateUser`.
- Tabel baru: kolom snake_case via `@map`, `TIMESTAMPTZ`, default `gen_random_uuid()`, invarian lewat CHECK di SQL migrasi. Query selalu dibatasi `user_id` dari sesi, jangan percaya ID dari klien. Endpoint yang memproses data kesehatan wajib `consentService.requireConsent`.
- Nama model Prisma auth sengaja `Users/Sessions/Accounts/Verifications` (adapter mencari delegate sesuai `modelName`); kolom auth masih camelCase, penamaan kolom ditentukan di Data Dictionary.

## Skrip operasional (di container)
- `server/scripts/tkpi/{parse,ingest,upload}.ts`: pipeline referensi TKPI (OCR → parse → `food_reference` + embedding `mistral-embed`; unggah PDF ke UploadThing). Berkas OCR/parsed tidak disimpan di repo; jalankan dengan `docker compose ... run --rm -v <folder>:/data:ro tester bun run scripts/tkpi/ingest.ts /data/parsed.json`. Kunci hanya dari env (`MISTRAL_API_KEY`, `UPLOADTHING_TOKEN`).

## Hal yang perlu diketahui
- Port host 5432/3000 dipakai proyek lain di mesin ini; beOkay memakai 5433 (DB) dan 3000 (API, bisa diubah via `API_HOST_PORT`).
- `src/generated/` (Prisma Client) di-generate, jangan diedit/commit.
- Rahasia hanya di `.env*` (gitignored). Jangan menaruh kredensial di file yang di-track.
- Image Postgres `pgvector/pgvector:pg17` dipilih untuk kebutuhan P2 (RAG); extension belum diaktifkan.
