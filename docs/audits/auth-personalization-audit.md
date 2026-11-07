# Audit & Gap Analysis — Authentication & Personalization

Stage 01 (audit) + Stage 02 (gap analysis). Tanggal audit: 8 November 2026.
Cakupan: repo `beOkay` pada commit `eb3a54d` (satu-satunya commit) ditambah perubahan lokal yang belum di-commit saat audit.
Aturan pengerjaan: tidak ada `git add/commit/push`; sejak instruksi pengguna di tengah audit, **semua eksekusi lewat Docker** (lihat `AGENTS.md`).

## 1. Ringkasan eksekutif

- Fondasi yang nyata hanya: Bun API minimal, Prisma 7 + PostgreSQL, **Better Auth 1.7.18** (email + password) dan migrasi `auth_init`. Backend auth yang aktif hanya `/api/auth/*` dan `/health`.
- Dari 54 kebutuhan: **0 EXISTS_AND_VALIDATED**, 6 EXISTS_BUT_INCOMPLETE, 1 EXISTS_WITH_DEFECT, 46 MISSING, 1 NOT_APPLICABLE.
- Aplikasi Flutter masih template counter bawaan. Tidak ada satu pun layar, router, state management, tema, atau klien jaringan.
- Tidak ada test sama sekali di server (0 berkas), tidak ada `docs/`, tidak ada koleksi Bruno.
- Ada 19 cacat teramati (bagian 6). Yang paling berdampak: sign-up langsung membuat sesi aktif tanpa verifikasi email, rate limiting mati di luar produksi, tidak ada strategi sesi untuk klien mobile, dan `db:generate` gagal di host karena berkas milik `root` dari container dev.
- Beberapa instruksi di prompt induk berbeda dengan keputusan repo (Drizzle vs Prisma, Hono vs `Bun.serve`). Repo yang menang; alasannya di bagian 3.

## 2. Metode dan bukti

Setiap temuan diberi sumber bukti. Tidak ada klaim tanpa bukti; yang belum terverifikasi ditandai **[belum diverifikasi]**.

| Kode | Arti |
|---|---|
| S | Dibaca dari kode/konfigurasi repo |
| D | Dibaca dari kode `node_modules/better-auth` (sumber pustaka) |
| R | Dijalankan: perintah dan hasilnya teramati |

Yang dijalankan selama audit:

| Langkah | Hasil |
|---|---|
| `docker compose up -d postgres` | Sehat dalam 6 dtk, `127.0.0.1:5433` |
| `db:migrate:deploy` pada DB dev kosong | `auth_init` berhasil diterapkan |
| `db:generate` | **Gagal**: `EACCES ... rm src/generated/prisma/internal` (D-01) |
| `bun index.ts` lalu `GET /health` | `{"status":"ok","db":true}` |
| 10 probe HTTP ke `/api/auth/*` | Hasil di bagian 4.4 |
| `bun test` (server) | `0 test files` |
| `flutter test` / `flutter analyze` (app) | 1 lulus (template counter) / `No issues found` |

Catatan metode: `db:migrate:deploy`, `bun index.ts`, `bun test`, dan `flutter *` di atas dijalankan di host, **sebelum** aturan "semua lewat Docker" diberlakukan. Hasilnya tetap bukti valid untuk audit. Dari Stage 03 seterusnya semuanya di container. Data uji (satu pengguna dan sesinya) sudah dihapus dari DB dev; API dan container Postgres sudah dihentikan; volume `beokay-dev_pgdata` tetap ada dengan `auth_init` terpasang.

## 3. Stack aktual vs preferensi prompt

| Lapisan | Prompt menyarankan | Aktual (bukti) | Keputusan |
|---|---|---|---|
| Runtime/HTTP | "Bun + Hono, mungkin" | `Bun.serve({ routes })` tanpa framework (S: `src/server.ts`); Hono tidak terpasang | **Pertahankan `Bun.serve`**. `server/CLAUDE.md` mewajibkan Bun-first; Hono = dependensi tanpa kebutuhan nyata |
| ORM | Drizzle | **Prisma 7.10.1** + `@prisma/adapter-pg` (S: `package.json`) | **Pertahankan Prisma**. `AGENTS.md`: "keputusan pengguna". Better Auth punya adapter Prisma (D) |
| Auth | Better Auth | Better Auth 1.7.18, `emailAndPassword` aktif (S) | Pertahankan; satu-satunya otoritas auth |
| Validasi | Zod | `zod 4.6.7` hanya sebagai dependensi transitif Better Auth (S: `bun.lock`) | **Jadikan dependensi langsung** saat Stage 06 |
| Test backend | runner kompatibel | `bun test` tersedia, 0 berkas (R) | `bun:test` di container |
| Mobile | Flutter + Riverpod | Flutter 3.44.4 / Dart 3.12.2, hanya SDK + `cupertino_icons` (S) | Tambah `flutter_riverpod`, `go_router`, `flutter_secure_storage`, `intl`, klien HTTP di Stage 07 |
| Desain | FigCraft | `design/beOkay-ui.figcraft` (26 layar fitness-metabolik, bukan set auth) | Buat berkas baru `design/figcraft/auth-personalization.figcraft` |
| API test | Bruno | CLI `bru` tidak ada di host (R); `docs/` belum ada | Bruno CLI lewat container Node (Stage 10) |
| Infra | Docker | `compose.yaml`, `compose.prod.yaml`, `server/Dockerfile` multi-stage (S) | Pertahankan; tambah service test terisolasi |

## 4. Temuan per kategori

### 4.1 Backend
- Titik masuk `index.ts` → `src/server.ts`. Hanya dua rute: `/api/auth/*` (diteruskan ke `auth.handler`) dan `/health` (S).
- `src/app.ts`, `src/plugins/cors.plugin.ts`, `src/plugins/db.plugin.ts` adalah **berkas kosong 0 byte** (R: `find -size 0`). Direktori `src/modules/*`, `src/agentic/*`, `src/infrastructure/{cache,llm,queue,storage,observability}`, `src/shared/*` kosong. Ini sisa scaffold dari arsitektur lain; tidak dipakai.
- Tidak ada: middleware auth untuk rute aplikasi, penanganan error terpusat, logging, request id, validasi input aplikasi, lapisan service/repository.
- Rute tak dikenal menghasilkan `404` bawaan Bun (R: `GET /api/me/profile` → 404).
- Penutupan proses (`SIGTERM`/`SIGINT`) benar: `server.stop()` lalu `prisma.$disconnect()` (S).

### 4.2 Database
- Satu migrasi: `20261107211003_auth_init` membuat `users`, `sessions`, `accounts`, `verifications` (PK UUID, FK `ON DELETE CASCADE`, unik `email` dan `token`, indeks `userId`/`identifier`) (S).
- Model Prisma auth dibuat oleh CLI: `Users/Sessions/Accounts/Verifications`, kolom **camelCase**; relasi bernama `sessionss`/`accountss` (artefak pluralisasi CLI, kosmetik).
- Belum ada: `user_profiles`, `health_profiles`, `user_settings`, `consent_records`, tabel progres onboarding, `audit_events`. Tidak ada RLS. Tidak ada CHECK constraint.
- Blueprint menetapkan kolom snake_case; `AGENTS.md` menunda penamaan kolom auth ke Data Dictionary yang belum ada.

### 4.3 Frontend / mobile
- `app/lib/main.dart` = counter bawaan (`MaterialApp` "Flutter Demo", seed ungu). `app/test/widget_test.dart` menguji counter itu, jadi **akan rusak** begitu `main.dart` diganti dan harus ditulis ulang.
- `pubspec.yaml`: tidak ada state management, router, penyimpanan aman, klien HTTP, l10n, aset, font. Nama paket `app`, `applicationId` Android `com.example.app` (S).
- `app/lib/beokay_tokens.dart` ada (ekspor variabel FigCraft: 15 warna + 13 angka) dan bisa menjadi dasar `AppColors/AppSpacing/AppRadius`.
- Font Inter tersedia di mesin sebagai TTF statis (Regular/SemiBold/Bold) tetapi belum dibundel; perlu berkas lisensi OFL saat dibundel.
- `flutter analyze` bersih, `flutter test` lulus (hanya karena kode masih template).

### 4.4 Keamanan: hasil probe langsung (R) dan sumber (D)

| # | Probe | Hasil teramati |
|---|---|---|
| 1 | `POST /api/auth/sign-up/email` | `200`; **langsung sesi aktif** (`Set-Cookie: better-auth.session_token; HttpOnly; SameSite=Lax; Max-Age=604800`), `emailVerified:false`. Token sesi juga ada di badan JSON |
| 2 | `sign-in/email` | `200`, cookie sama |
| 3 | `get-session` dengan cookie | Mengembalikan sesi + pengguna. `ipAddress` bernilai `""` |
| 4 | Sign-up email yang sudah ada | `422 USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL` → **membocorkan keberadaan akun** |
| 5 | Password `123` | `PASSWORD_TOO_SHORT` (batas bawaan Better Auth) |
| 6 | Origin `http://evil.example` | `403 INVALID_ORIGIN` |
| 7 | Password salah vs email tak dikenal | Pesan identik `INVALID_EMAIL_OR_PASSWORD` (baik) |
| 8 | `send-verification-email`, `request-password-reset` | `400 VERIFICATION_EMAIL_NOT_ENABLED` / `RESET_PASSWORD_DISABLED` |
| 9 | `list-sessions`, `sign-out`, `get-session` | Daftar sesi tampil; sign-out `{success:true}`; sesudahnya `null` |
| 10 | `OPTIONS` dari origin lain | `404`, tanpa header CORS |
| D | `rateLimit.enabled` | Bawaan `options.rateLimit?.enabled ?? isProduction` (`create-context.mjs:172`) → **mati di dev/test** |
| D | Plugin tersedia di 1.7.18 | `bearer`, `multi-session`, `email-otp`, `two-factor`, `username`, `open-api`; **tidak ada** paket `@better-auth/expo` terpasang (dan tidak relevan untuk Flutter) |
| D | Endpoint native | `changePassword`, `listSessions`, `revokeSessions`, `revokeOtherSessions`, `requestPasswordReset`, `resetPassword`, `sendVerificationEmail`, `requireEmailVerification`, `trustedOrigins` ada di API pustaka |

Header `set-auth-token` milik plugin `bearer` **[belum diverifikasi]**; diverifikasi di Stage 04.

### 4.5 Test, dokumentasi, infrastruktur
- Server: 0 berkas test; `tests/{unit,integration,e2e}` kosong (R).
- Dokumentasi: `docs/` tidak ada; tidak ada koleksi Bruno; `server/README.md` hanya templat `bun init`.
- Dev compose: Postgres sehat, API tanpa healthcheck, **berjalan sebagai root dengan bind mount** (S: `Dockerfile` target `dev`; R: berkas `root:root` di `src/generated/prisma/{internal,models}`). Prod: image non-root `bun`, `read_only`, `cap_drop: ALL` (baik).
- `compose.yaml` dev memberi fallback secret dev jika env kosong (wajar untuk dev); `compose.prod.yaml` memakai `:?` sehingga wajib diisi (baik).

## 5. Matriks kebutuhan

Status: EV = EXISTS_AND_VALIDATED · EI = EXISTS_BUT_INCOMPLETE · ED = EXISTS_WITH_DEFECT · M = MISSING · NA = NOT_APPLICABLE.
Prioritas: P0 = blokir fitur lain; P1 = wajib selesai di rangkaian ini; P2 = pelengkap.
Verifikasi merujuk skenario A–J pada prompt induk.
"BA" = Better Auth.

### A. Authentication

| ID | Kebutuhan | Status | Bukti & cacat | Pekerjaan wajib | Dep | Prio | Verifikasi |
|---|---|---|---|---|---|---|---|
| A1 | Registrasi | EI | Endpoint BA hidup (R-1). Tidak ada UI/tes. Sesi dibuat sebelum verifikasi (D-02); duplikat membocorkan akun (D-03) | `requireEmailVerification`, validasi nama/password, UI, tes | A3 | P0 | Unit+integrasi, skenario A |
| A2 | Login aman | EI | Endpoint hidup, pesan error seragam (R-7). Tidak ada UI/tes; rate limit mati (D-04) | Rate limit eksplisit, UI, tes | A8 | P0 | Skenario B, J |
| A3 | Verifikasi email | M | `VERIFICATION_EMAIL_NOT_ENABLED` (R-8). Tidak ada pengirim email | `sendVerificationEmail` + `EmailSender`, layar verifikasi | Keputusan email (bag. 7) | P0 | Skenario A |
| A4 | Reset password | M | `RESET_PASSWORD_DISABLED` (R-8) | `sendResetPassword`, layar lupa/reset, tanpa enumerasi | A3 | P0 | Skenario D |
| A5 | Persistensi sesi | EI | Sesi server + cookie berjalan (R-3). Tidak ada penyimpanan di klien; Dart tidak punya SDK BA (D-07) | Strategi mobile (bearer) + penyimpanan aman | A7 | P0 | Skenario B, I |
| A6 | Logout | EI | `sign-out` berhasil (R-9). Tidak ada UI; pembersihan kredensial klien belum ada | UI, hapus token lokal | A5 | P1 | Skenario B |
| A7 | Routing terautentikasi | M | Tidak ada router Flutter; tidak ada guard server untuk rute aplikasi (D-08) | Middleware sesi server; `go_router` + satu keputusan redirect | A5, B* | P0 | Skenario B, I |
| A8 | Keamanan akun | ED | Rate limit mati (D-04), tanpa `trustedOrigins` (D-05), enumerasi (D-03), sesi pra-verifikasi (D-02), tanpa CORS (D-06) | Konfigurasi BA eksplisit, tes keamanan | — | P0 | Bruno 07, skenario H, J |
| A9 | Manajemen sesi | EI | `list-sessions` hidup (R-9); IP sesi kosong (D-15) | UI sesi, revoke lainnya, IP klien | A5 | P1 | Skenario I |

### B. Onboarding

| ID | Kebutuhan | Status | Bukti & cacat | Pekerjaan wajib | Dep | Prio | Verifikasi |
|---|---|---|---|---|---|---|---|
| B1 | Layar sambutan premium | M | Desain UI-01 ada di berkas FigCraft lama sebagai referensi; belum ada layar Flutter | Desain baru + implementasi | Stage 03 | P1 | Visual QA |
| B2 | Pengenalan platform | M | — | Desain + implementasi (layar 06) | Stage 03 | P1 | Visual QA |
| B3 | Transisi registrasi → onboarding | M | — | Keputusan rute terpusat | A7 | P1 | Skenario A |
| B4 | Onboarding multi-langkah | M | — | Layar 07–10 + state | B5 | P1 | Skenario A |
| B5 | Pelacakan progres | M | Tidak ada tabel progres | Tabel + API `/api/me/onboarding` | Stage 05 | P0 | Unit onboarding |
| B6 | Simpan & lanjutkan | M | — | Persisten server, idempoten | B5 | P0 | Skenario C |
| B7 | Alur pertanyaan bersyarat | M | — | Aturan progresif (mis. tipe diabetes hanya bila terdiagnosis) | E1 | P1 | Unit health profile |
| B8 | Penyelesaian onboarding | M | — | `POST /complete` tervalidasi, idempoten | B5, C*, D*, E*, F* | P0 | Skenario A, tes duplikat |
| B9 | Redirect pengguna kembali | M | — | Satu fungsi keputusan rute, cegah loop | A7, B5 | P0 | Skenario B, C |

### C. Persetujuan data kesehatan

| ID | Kebutuhan | Status | Bukti & cacat | Pekerjaan wajib | Dep | Prio | Verifikasi |
|---|---|---|---|---|---|---|---|
| C1 | Informasi privasi | M | Teks privasi belum ada; perlu dari tim/legal | Konten kebijakan v1 (draf, perlu review) | — | P1 | Review konten |
| C2 | Penjelasan tujuan | M | — | Daftar tujuan wajib vs opsional | C1 | P1 | Visual QA |
| C3 | Pencatatan persetujuan | M | Tidak ada `consent_records` | Tabel + endpoint, bukan boolean | Stage 05 | P0 | Unit consent |
| C4 | Versi kebijakan | M | — | Registri kebijakan bertipe; tolak versi tak dikenal | C3 | P0 | Bruno "Invalid Policy Version" |
| C5 | Kontrol persetujuan opsional | M | — | Tanpa pra-pilih | C2 | P1 | UI test |
| C6 | Riwayat persetujuan | M | — | Baris historis tak dihapus | C3 | P1 | Unit consent |
| C7 | Penarikan persetujuan | M | — | Endpoint `withdraw` + efek ke izin | C3 | P0 | Skenario E |
| C8 | Penegakan di server | M | Tidak ada middleware izin | Guard `requireConsent(purpose)` | C3, A7 | P0 | Bruno "Missing Consent" |

### D. Profil pribadi

| ID | Kebutuhan | Status | Bukti & cacat | Pekerjaan wajib | Dep | Prio | Verifikasi |
|---|---|---|---|---|---|---|---|
| D1 | Identitas | M | `users.name` dari BA sudah ada (satu-satunya data identitas) | `user_profiles` | Stage 05 | P0 | Unit profile |
| D2 | Nama tampilan | M | Duplikasi dengan `users.name` harus dihindari | Tentukan sumber tunggal nama | D1 | P0 | Unit profile |
| D3 | Demografi relevan | M | — | Minimum: tahun lahir (sesuai blueprint) | D1 | P1 | Unit profile |
| D4 | Edit profil | M | — | `PATCH /api/me/profile` + layar 13 | D1 | P1 | Skenario F |
| D5 | Kelengkapan profil | M | — | Dihitung dari field, bukan disimpan | D1 | P2 | Unit profile |
| D6 | Persistensi | M | — | Migrasi + repository | D1 | P0 | Integrasi |
| D7 | Validasi | M | Zod belum jadi dependensi langsung | Skema Zod per endpoint | — | P0 | Bruno "Invalid Input" |

### E. Profil kesehatan

| ID | Kebutuhan | Status | Bukti & cacat | Pekerjaan wajib | Dep | Prio | Verifikasi |
|---|---|---|---|---|---|---|---|
| E1 | Konteks diabetes | M | Tabel `health_profiles` belum ada | Tabel + API | Stage 05 | P0 | Unit health |
| E2 | Status diagnosis (lapor sendiri) | M | — | Enum termasuk `unknown`/`undisclosed` | E1 | P0 | Unit health |
| E3 | Tipe diabetes | M | — | Enum + aturan bersyarat | E2 | P1 | Unit health |
| E4 | Tanggal/tahun diagnosis | M | — | Validasi (tidak di masa depan, ≥ tahun lahir) | E1, D3 | P1 | Unit "invalid dates" |
| E5 | Konteks pengobatan dasar | M | — | Enum multi-pilih tanpa dosis | E1 | P1 | Unit health |
| E6 | Edit profil kesehatan | M | — | `PUT/PATCH` + layar 14 | E1 | P1 | Skenario F |
| E7 | Provenance | M | — | Kolom sumber (`user_reported`); tidak mengklaim terverifikasi | E1 | P0 | Unit health |
| E8 | Kelayakan & keselamatan | M | — | `eligibility_status` deterministik; tanpa saran medis | E2 | P1 | Unit health |

### F. Lokalisasi & pengukuran

| ID | Kebutuhan | Status | Bukti & cacat | Pekerjaan wajib | Dep | Prio | Verifikasi |
|---|---|---|---|---|---|---|---|
| F1 | Bahasa | M | Tidak ada l10n di Flutter | `id-ID` default; `en` hanya bila terjemahan lengkap | Stage 07 | P1 | Unit preferences |
| F2 | Zona waktu | M | — | Validasi IANA di server (`Intl.supportedValuesOf`) | G-tabel | P1 | Unit "invalid timezone" |
| F3 | Satuan glukosa | M | — | `mg/dL`/`mmol/L`; tidak menulis ulang nilai sumber | — | P0 | Unit preferences |
| F4 | Preferensi persisten | M | — | `user_settings` | Stage 05 | P0 | Skenario G |
| F5 | Format sesuai locale | M | — | `intl` di Flutter | F1 | P2 | Widget test |
| F6 | Kontrak konversi unit | M | Faktor 18,016 (mg/dL↔mmol/L) | Fungsi konversi murni + tes tepi; **hanya tampilan** | F3 | P1 | Unit preferences |

### G. Pengaturan aplikasi

| ID | Kebutuhan | Status | Bukti & cacat | Pekerjaan wajib | Dep | Prio | Verifikasi |
|---|---|---|---|---|---|---|---|
| G1 | Pengaturan akun | M | — | Layar 15, email dari BA | A5 | P1 | UI test |
| G2 | Tampilan | M | — | Hanya opsi yang berfungsi (mis. ukuran teks; tema gelap hanya bila ada) | Stage 07 | P2 | Widget test |
| G3 | Notifikasi | NA | Belum ada fitur notifikasi/pengingat (itu P1 blueprint) | Tidak ditampilkan | — | — | — |
| G4 | Aksesibilitas | M | — | Ukuran teks, kurangi gerak | Stage 07 | P1 | Visual QA |
| G5 | Privasi | M | — | Tautan ke manajemen persetujuan (layar 16) | C* | P1 | UI test |
| G6 | Navigasi keamanan akun | M | — | Layar 17 | A9 | P1 | UI test |
| G7 | Kontrol sesi | EI | Endpoint BA ada (D); belum ada UI | Daftar sesi, cabut lainnya, logout | A9 | P1 | Skenario I |

Lintas-fitur (di luar A–G): **Desain** (FigCraft) M · **Tes server** M · **Tes Flutter** EI (hanya templat) · **Bruno** M · **Dokumentasi** M · **Infrastruktur uji terisolasi** M.

## 6. Cacat teramati

| ID | Cacat | Bukti | Dampak | Prio | Perbaikan (stage) |
|---|---|---|---|---|---|
| D-01 | Berkas `root:root` di `src/generated/prisma/{internal,models}`; `db:generate` di host gagal `EACCES` | R | Build/generate rusak; berkas tak bisa dihapus pengguna | P0 | Container jalan sebagai UID host; pengguna perlu `sudo chown -R $USER: server/src/generated` sekali (Stage 04) |
| D-02 | Sign-up langsung membuat sesi untuk akun belum terverifikasi | R-1 | Verifikasi email tidak bermakna | P0 | `requireEmailVerification` (04) |
| D-03 | Sign-up email duplikat → `422` yang menyebut akun sudah ada | R-4 | Enumerasi akun | P0 | Perilaku anti-enumerasi + verifikasi (04); **[belum diverifikasi]** apakah BA 1.7.18 menyamarkan saat verifikasi wajib |
| D-04 | Rate limit mati di luar produksi | D | Brute force tak teruji di dev/test | P0 | Aktifkan eksplisit + aturan ketat untuk sign-in/reset (04) |
| D-05 | Tanpa `trustedOrigins`; request native tanpa header Origin belum diuji | S, R-6 | Celah CSRF jika ada klien web | P1 | Daftar eksplisit dari env (04) |
| D-06 | Tidak ada CORS (`OPTIONS` → 404) | R-10 | Hanya bermasalah bila target web dipakai | P2 | Tentukan setelah keputusan platform (04) |
| D-07 | Tanpa strategi sesi mobile; hanya cookie; Dart tanpa SDK BA | R-1, D | Sesi tidak persisten di klien | P0 | Plugin `bearer` + token di secure storage; verifikasi header (04, 07) |
| D-08 | Berkas kosong (`app.ts`, `cors.plugin.ts`, `db.plugin.ts`), direktori scaffold kosong, tanpa error handler/logging | R | Struktur menyesatkan | P1 | Diganti struktur `features/*` (06) |
| D-09 | 0 test server; test Flutter hanya templat yang akan rusak | R | Tanpa jaring pengaman | P0 | Stage 08–09 |
| D-10 | Flutter = template counter; `com.example.app`; tanpa router/state/tema/font | S | Seluruh UI nol | P0 | Stage 07; **ID aplikasi perlu keputusan pengguna** |
| D-11 | `AGENTS.md` melarang model domain, verifikasi email, reset password, UI Flutter "tanpa diminta" | S | Konflik dengan tugas ini | P1 | Diminta eksplisit sekarang; perbarui `AGENTS.md` di akhir (12) |
| D-12 | Service `api` dev berjalan sebagai root + bind mount; tanpa healthcheck | S, R | Akar D-01 | P0 | `user:` di compose + healthcheck (04) |
| D-13 | Fallback secret dev di `compose.yaml` | S | Aman hanya untuk dev | P2 | Tetap; dokumentasikan |
| D-14 | Kolom auth camelCase vs konvensi blueprint snake_case; relasi `sessionss/accountss` | S | Inkonsistensi penamaan | P2 | Ditunda ke Data Dictionary (AGENTS) |
| D-15 | `ipAddress` sesi tersimpan `""` | R-3 | Daftar sesi tanpa IP | P2 | Teruskan IP klien dari `Bun.serve` (04) |
| D-16 | `.gitignore` memuat `.claude` | S | Pagar pengaman `settings.json` tak ter-track | P2 | Keputusan pengguna |
| D-17 | Zod hanya transitif | S | Versi bisa bergeser diam-diam | P1 | Dependensi langsung (06) |
| D-18 | Bruno CLI tidak ada; aturan Docker-only | R | Tidak bisa menjalankan koleksi di host | P1 | Container Node + `@usebruno/cli` (10); **[belum diverifikasi]** butuh unduh paket |
| D-19 | Flutter hanya terpasang di host; image Flutter belum ada lokal | R | Aturan Docker-only butuh image Flutter | P1 | Lihat bagian 7, keputusan 6 |

## 7. Keputusan dan asumsi

| # | Hal | Keputusan / asumsi | Status |
|---|---|---|---|
| 1 | ORM | Prisma 7 (bukan Drizzle) | Final (keputusan pengguna di `AGENTS.md`) |
| 2 | HTTP | `Bun.serve` + modul `features/*`; tanpa Hono | Final |
| 3 | Validasi | Zod 4 sebagai dependensi langsung | Asumsi |
| 4 | **Pengiriman email** | Antarmuka `EmailSender`; dev/test: **Mailpit** (container) agar tautan verifikasi/reset bisa diuji end-to-end; produksi: penyedia **belum diputuskan** | **Perlu keputusan pengguna sebelum produksi.** Untuk Stage 04 saya lanjut dengan Mailpit |
| 5 | Sesi mobile | Plugin `bearer` + `flutter_secure_storage` | Asumsi, diverifikasi di Stage 04 |
| 6 | **Flutter di Docker** | Image Flutter stabil (mis. `ghcr.io/cirruslabs/flutter`) untuk `analyze`/`test`; belum ada lokal, perlu unduh | **Perlu persetujuan unduh** di Stage 07 |
| 7 | Kebijakan persetujuan | Registri bertipe di kode (versi + teks), catatan di DB merujuk versi | Asumsi |
| 8 | Penamaan tabel baru | `user_profiles`, `health_profiles`, `user_settings`, `consent_records`, `onboarding_progress`, `audit_events`; kolom snake_case via `@map` | Asumsi, selaras blueprint |
| 9 | ID aplikasi Android/iOS | Dibiarkan `com.example.app` sampai Anda memutuskan | **Perlu keputusan pengguna** |
| 10 | Teks privasi/legal | Draf netral; wajib direview pihak berwenang | Batasan |
| 11 | Aset foto | Placeholder grayscale seperti di desain sebelumnya; foto berlisensi dari Anda | Batasan |

## 8. Rencana bergantung dan titik berhenti

Setiap stage berhenti agar bisa Anda commit. Semua perintah di Docker.

| Stage | Isi | Bergantung pada | Keluaran utama |
|---|---|---|---|
| 01–02 | Audit + gap analysis | — | Dokumen ini ✔ |
| 03 | Desain FigCraft (token, komponen, 17 layar) | audit | `design/figcraft/auth-personalization.figcraft`, `previews/`, `docs/design/auth-personalization-ui-spec.md` |
| 04 | Fondasi Better Auth + Docker | 03 tidak wajib; keputusan #4 | Verifikasi email, reset, rate limit, origin, bearer, Mailpit, user container non-root |
| 05 | Database | 04 | Migrasi + `docs/database/identity-consent-profile.md` |
| 06 | Backend `features/*` | 05 | Service, repository, Zod, guard consent, API `/api/me/*` |
| 07 | Flutter | 03, 04, 06; keputusan #6, #9 | Tema, router, 17 layar, klien |
| 08 | Unit test | 06 | `bun:test` + Flutter test, di Docker |
| 09 | Integrasi | 05, 06 | DB uji terisolasi, skenario A–J sisi server |
| 10 | Bruno | 06, 09 | Koleksi + instruksi CLI terverifikasi |
| 11 | E2E + QA visual | 07, 10 | Bukti nyata, perbandingan dengan FigCraft |
| 12 | Audit akhir + laporan | semua | `docs/reports/...`, `AGENTS.md` diperbarui |

## 9. Risiko dan blokir

- **Email produksi belum ada penyedia** → verifikasi/reset hanya teruji lewat Mailpit sampai ada keputusan.
- **Docker-only untuk Flutter** → perlu unduh image besar; tanpa itu `analyze`/`test` Flutter tidak bisa dijalankan sesuai aturan.
- **Berkas milik root** (D-01) → butuh satu perintah `sudo` dari Anda; sampai itu dilakukan, hanya container yang bisa meng-generate Prisma Client.
- **Anti-enumerasi** (D-03) dan **`set-auth-token`** (D-07) masih asumsi sampai diuji di Stage 04.
- **Konten legal** bukan nasihat hukum; wajib direview.
- Desain lama (26 layar) dan desain baru harus konsisten; token tunggal dari `beokay_tokens.dart`.

## 10. Rencana verifikasi

Skenario A–J pada prompt induk dipetakan ke: unit (Stage 08), integrasi dengan DB terisolasi (09), koleksi Bruno + Bruno CLI (10), dan alur nyata + perbandingan visual (11). Tidak ada hasil tes yang dilaporkan sebelum benar-benar dijalankan.
