# Arsitektur — Authentication & Personalization (backend)

Bagian Flutter ditambahkan saat tahap UI.

## Batas dan dependensi
```
server.ts
 ├─ features/auth          (Better Auth, guard sesi, halaman verifikasi/reset)
 ├─ features/consent       (registri kebijakan, riwayat persetujuan)
 ├─ features/profile       → health-profile (hanya eligibility), auth (updateUser)
 ├─ features/health-profile→ consent
 ├─ features/preferences
 └─ features/onboarding    → consent (+ membaca tabel profil/kesehatan/pengaturan)
shared/{errors,http,audit}   infrastructure/{database,email}   config/env.ts
```
Panah satu arah; tidak ada siklus. `features/*` tidak mengimpor satu sama lain kecuali yang tertera. Setiap fitur memiliki `routes` (HTTP), `service` (aturan bisnis, transaksi), `repository` (Prisma), `schema` (Zod).

## Keputusan
- **Better Auth satu-satunya otoritas** identitas, kata sandi, sesi, verifikasi, reset. Tidak ada tabel atau mekanisme kata sandi lain. Status verifikasi email tidak diduplikasi di tabel aplikasi.
- **Sesi mobile = plugin `bearer`.** Token dikembalikan di header `set-auth-token`; klien menyimpannya di penyimpanan aman.
- **Email via SMTP** (`nodemailer`): satu antarmuka `EmailSender`, penyedia apa pun yang mendukung SMTP. Dev/uji memakai Mailpit sehingga email tidak keluar. Pengiriman tidak ditunggu (anti timing). Log hanya memuat jenis email, bukan alamat atau tautan.
- **Status onboarding diturunkan**, bukan disimpan; penyelesaian memakai `SELECT … FOR UPDATE` dalam transaksi sehingga idempoten dan aman terhadap permintaan paralel; `version` untuk konkurensi optimistik.
- **Persetujuan ditegakkan di server** lewat `consentService.requireConsent`; versi kebijakan lama tidak dianggap sah (`reconsent_required`).
- **Validasi** di batas HTTP dengan Zod; badan permintaan dibatasi 64 KB dan harus `application/json`.
- **Kesalahan**: satu format; error tak terduga dicatat tanpa pesan atau data dan dijawab `500` generik.
- **Log** JSON per permintaan (`requestId`, metode, path tanpa query, status, durasi, `userId`); tanpa header, badan, token.
- **Nama tampilan** satu sumber (`users.name`).
- **Tanpa CORS**: klien adalah aplikasi native. Perlu dipertimbangkan ulang bila target web dipakai.

## Docker
Semua eksekusi di container (lihat `AGENTS.md`). Container dev dan uji berjalan sebagai UID host (`HOST_UID`/`HOST_GID`) sehingga tidak membuat berkas milik root pada bind mount. Stack uji (`compose.test.yaml`) memakai Postgres di tmpfs, Mailpit, dan tanpa port yang dipublikasikan.

## Batasan yang diketahui
- Rate limit disimpan di memori proses: berlaku untuk satu instance. Skala horizontal butuh penyimpanan bersama.
- Teks kebijakan persetujuan adalah draf, belum ditinjau hukum.
- Belum ada tes otomatis (tahap berikutnya); verifikasi di tahap ini berupa uji eksploratif terhadap API yang berjalan.
