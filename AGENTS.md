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
- `app/` — Flutter (scaffold bawaan, belum dikerjakan).
- `compose.yaml` (dev), `compose.prod.yaml` (prod), `.env.example`, `.env.prod.example`.

## Cakupan saat ini (jangan melebar)
- Sudah: koneksi DB + Prisma + `/health`; stack Docker dev & prod; **Better Auth** (email+password, PK UUID, tabel `users/sessions/accounts/verifications`, handler di `/api/auth/*`, migrasi `auth_init`).
- **Belum, dan jangan dibuat tanpa diminta**: model/tabel domain (meal, glucose, dst.), modul domain, verifikasi email/reset password (menunggu penyedia email), UI Flutter.
  Skema P0 menunggu 4 artefak: Data Dictionary, Physical ERD, Screen Specification, UI–API Contract Matrix.
- Desain UI dikerjakan di Figma (figcraft) lebih dulu, baru implementasi.

## Perintah (jalankan dari `server/` kecuali disebut)
- Dev stack (root): `docker compose up --build` — API `127.0.0.1:3000`, Postgres `127.0.0.1:5433`.
- Prod stack (root): `docker compose -f compose.prod.yaml --env-file .env.prod up -d --build`.
- `bun run typecheck` · `bun run db:generate` · `bun run db:migrate:dev` · `bun run db:migrate:deploy` · `bun run db:studio`.
- **Pakai script `db:*`, bukan `bunx prisma ...`**: `bunx`/`bun run prisma` tidak memuat `.env` untuk `prisma.config.ts` (DATABASE_URL tidak ter-resolve). Script memanggil `bun --bun ./node_modules/.bin/prisma`.

## Konvensi data (dari blueprint, berlaku saat skema dibuat)
- PK `UUID`, waktu `TIMESTAMPTZ`, ukuran `NUMERIC`, `JSONB` hanya untuk metadata variabel.
- Nilai tidak diketahui = `NULL`, bukan `0`. Prediksi tidak disimpan di tabel pengukuran.
- Semua query dibatasi kepemilikan `user_id`. Koreksi data lewat `record_revisions`.
- Auth = Better Auth (keputusan pengguna). Model auth di `prisma/schema.prisma` dihasilkan CLI: ubah `src/lib/auth.ts` lalu `bun run auth:generate`, bukan edit manual. Jangan buat mekanisme password sendiri.
- Nama model Prisma auth sengaja `Users/Sessions/Accounts/Verifications` (adapter mencari delegate sesuai `modelName`); kolom auth masih camelCase, penamaan kolom ditentukan di Data Dictionary.

## Hal yang perlu diketahui
- Port host 5432/3000 dipakai proyek lain di mesin ini; beOkay memakai 5433 (DB) dan 3000 (API, bisa diubah via `API_HOST_PORT`).
- `src/generated/` (Prisma Client) di-generate, jangan diedit/commit.
- Rahasia hanya di `.env*` (gitignored). Jangan menaruh kredensial di file yang di-track.
- Image Postgres `pgvector/pgvector:pg17` dipilih untuk kebutuhan P2 (RAG); extension belum diaktifkan.
