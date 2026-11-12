# Deploy di Vercel + Neon

Status 12 November 2026: API produksi berjalan di **https://beokay-api.vercel.app** (Vercel, proyek `beokay-api`, region `sin1`, runtime Bun 1.4), basis data di **Neon** (proyek `beokay`, `aws-ap-southeast-1`, Postgres 18, org Free). Stack Docker (`compose.prod.yaml`) tetap bisa dipakai; dokumen ini hanya untuk jalur serverless.

## 1. Apa berjalan di mana

| Bagian | Di Docker/VPS | Di Vercel + Neon |
|---|---|---|
| API HTTP | `bun src/server.ts` | `Bun.serve()` yang sama, dideteksi Vercel lewat `server/index.ts` (preset Bun, Fluid compute) |
| Postgres | container `pgvector/pgvector:pg17` | Neon; aplikasi memakai URL **pooled**, migrasi memakai URL **direct**; ekstensi `vector` dan `pg_trgm` aktif |
| Pekerja latar (outbox, pengingat kotak masuk, push, sapuan hasil, siklus tantangan, nudge, sinkron edukasi, retensi) | `setInterval` di proses API | dimatikan lewat env (`*_WORKER_ENABLED=false`, `PUSH_DISPATCH_ENABLED=false`); diganti **`/internal/jobs/tick`** yang dipicu penjadwal. Tiap job punya interval sendiri dan kunci di tabel `job_runs`, jadi tick ganda atau bersamaan tidak menjalankan job dua kali |
| Tugas setelah respons (kirim email, push, catat pemakaian, run agen latar) | promise biasa | `background()` → `waitUntil` dari `@vercel/functions` |
| WebSocket `/api/me/realtime` | satu proses | didukung Vercel; koneksi terikat ke satu instance. Untuk meneruskan pesan antar-instance isi `REALTIME_REDIS_URL` (opsional). Sudah aktif di produksi (log `realtime_bus_connected`). Tanpa itu, aplikasi tetap memuat kotak masuk lewat HTTP |
| Pembatas laju | memori proses | tetap memori, **per instance** (lebih longgar bila Vercel menjalankan beberapa instance) |
| Email (verifikasi, reset kata sandi) | Mailpit/SMTP | SMTP pihak ketiga (**belum diisi**, lihat §3) |
| Push | FCM | FCM (opsional, belum diisi) |
| Pencarian semantik, OCR, model bahasa | Mistral | Mistral (`MISTRAL_API_KEY` sudah dipasang) |

Berkas: `server/vercel.json` (Bun 1.4.x, region, `bun run db:generate` saat build, cron harian, `includeFiles` untuk paket `@better-auth/*` yang tidak ikut terdeteksi pelacak berkas; polanya `{node_modules,server/node_modules}/@better-auth/**` agar cocok untuk deploy dari `server/` maupun dari root), `.vercelignore` di root (wajib: `app/build` 3,7 GB), `server/.vercelignore`.

**Root Directory proyek Vercel = `server`** dan proyek tersambung ke GitHub (`misbahul45/beOkay`, branch `main`), jadi push ke `main` otomatis membangun produksi dari `server/`. Penautan CLI (`.vercel/`) ada di **root repo**, bukan di `server/`: jalankan `vercel deploy --prod` dari root. Menjalankannya dari `server/` gagal (`server/server` tidak ada).

## 2. Yang sudah diverifikasi di produksi

- Migrasi 31 berkas diterapkan ke Neon; data `food_reference` (1.037 TKPI + 45 kurasi, semua dengan embedding) dan 254 baris resep disalin dari DB dev.
- `/internal/jobs/tick` dengan `CRON_SECRET`: 8 job berjalan `OK` (push dilewati karena FCM belum diisi). Tanpa secret: 404.
- Uji asap (skrip sementara, tidak di repo), 17/17 lulus: daftar, masuk (bearer), persetujuan, catat glukosa, pencarian makanan semantik, jawaban keselamatan dan statistik Asisten, tautan dan halaman pendamping, impor dan ringkasan CGM, ekspor FHIR, edukasi produksi menyembunyikan draf, sinkron luring, WebSocket (`hello` diterima), `/metrics` tertutup, hapus akun (akun uji tidak tersisa). Email verifikasi disimulasikan lewat DB karena SMTP belum ada.
- Latensi uji asap: catat glukosa ~150 ms, pencarian makanan ~500 ms (termasuk embedding Mistral), pesan Asisten 650–850 ms; permintaan pertama setelah lama diam (Neon dan fungsi bangun) ~1,5–2 dtk.

## 3. Layanan gratis yang perlu kunci dari pemilik

| Kebutuhan | Rekomendasi gratis | Batas gratis | Variabel |
|---|---|---|---|
| **Email (wajib, tanpa ini pendaftaran tidak bisa diverifikasi)** | [Brevo](https://www.brevo.com/free-smtp-server/) SMTP | 300 email/hari, tanpa kartu kredit; alamat pengirim diverifikasi lewat email, domain tidak wajib | `SMTP_HOST=smtp-relay.brevo.com`, `SMTP_PORT=587`, `SMTP_USER` (login Brevo), `SMTP_PASS` (SMTP key), `EMAIL_FROM="beOkay <alamat-terverifikasi>"` |
| Alternatif email | Gmail SMTP dengan App Password (butuh 2FA) | ~500/hari | `SMTP_HOST=smtp.gmail.com`, `SMTP_PORT=465`, `SMTP_SECURE=true`, `SMTP_USER`, `SMTP_PASS` |
| **Penjadwal tiap 5–10 menit (wajib untuk pengingat kotak masuk, outbox)** | [cron-job.org](https://www.cron-job.org/) | gratis, interval minimal 1 menit, header kustom didukung, batas waktu 30 dtk (tick butuh ~2 dtk) | job GET `https://beokay-api.vercel.app/internal/jobs/tick`, header `Authorization: Bearer <CRON_SECRET>`, tiap 5 menit |
| Alternatif penjadwal | [Upstash QStash](https://upstash.com/qstash/pricing) | 1.000 pesan/hari (tiap 5 menit = 288/hari) | jadwal ke URL yang sama, header `Upstash-Forward-Authorization: Bearer <CRON_SECRET>` |
| **Penjadwal aktif (utama)**: Upstash QStash, jadwal `beokay-jobs-tick` (`*/5 * * * *`, GET, tanpa retry, header Authorization diteruskan) | akun free: 1.000 pesan/hari (288 dipakai), 10 jadwal; dibuat lewat Developer API | Lihat §11 |
| **Penjadwal cadangan**: GitHub Actions `.github/workflows/jobs-tick.yml` (tiap 10 menit) | gratis di repo; jadwal bisa terlambat beberapa menit dan berhenti setelah 60 hari tanpa aktivitas repo | secret repo `BEOKAY_API_URL` dan `BEOKAY_CRON_SECRET` terpasang; dijalankan manual 12 Nov 2026 → `HTTP 200` |
| Realtime antar-instance | [Upstash Redis](https://upstash.com/pricing/redis) database `beokay-realtime` (free, `ap-southeast-1`, TLS) **sudah dipasang** | 256 MB, 500 ribu perintah/bulan | `REALTIME_REDIS_URL` (sensitif di Vercel) |
| Push saat aplikasi tertutup (opsional) | Firebase Cloud Messaging | gratis | `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON`; aplikasi butuh `google-services.json` |

Vercel Cron (paket Hobby) hanya boleh sekali sehari; `vercel.json` memakainya sebagai cadangan pukul 02.00 WIB (retensi tetap jalan walau penjadwal eksternal mati).

## 4. Memasang kunci

Semua nilai rahasia disimpan di `/.env.deploy` (gitignored, izin 600). Untuk menambah kunci baru, tulis sendiri ke berkas itu, misalnya:

```bash
# di root repo; nilai diberi tanda kutip tunggal
echo "SMTP_USER='login-brevo@contoh.com'" >> .env.deploy
echo "SMTP_PASS='xsmtpsib-...'" >> .env.deploy
echo "EMAIL_FROM='beOkay <pengirim-terverifikasi@contoh.com>'" >> .env.deploy
```

Lalu pasang ke Vercel tanpa menampilkan nilainya dan deploy ulang:

```bash
cd server
vercel env add SMTP_HOST production --force <<< 'smtp-relay.brevo.com'
vercel env add SMTP_USER production --force --sensitive    # tempel nilai saat diminta
vercel env add SMTP_PASS production --force --sensitive
vercel env add EMAIL_FROM production --force
vercel deploy --prod
```

`CRON_SECRET` produksi ada di `.env.deploy` (`PROD_CRON_SECRET`). Untuk cron-job.org/QStash, salin nilainya dari berkas itu.

## 5. Operasi rutin

```bash
# Migrasi ke Neon (di container; URL direct, bukan pooled)
NEON_DIRECT_URL=... docker compose run --rm --no-deps -T -e DATABASE_URL="$NEON_DIRECT_URL" api bun run db:migrate:deploy

# Deploy
vercel deploy --prod        # dari root repo; Root Directory proyek = server

# Status job
curl -H "Authorization: Bearer $CRON_SECRET" https://beokay-api.vercel.app/internal/jobs/status

# Log runtime
vercel logs https://beokay-api.vercel.app --no-follow --limit 50
```

Jangan `source .env.deploy` langsung di shell: URL Neon memuat `&`. Baca nilainya dengan alat yang mengurai kutip (mis. `python3 -c` + `shlex`) atau salin manual.

Aplikasi Android untuk server ini: `flutter build apk --debug --dart-define=API_BASE_URL=https://beokay-api.vercel.app` (rilis tetap butuh `key.properties`).

## 6. Batas yang perlu diketahui

1. **Hobby Vercel**: durasi fungsi maks. 300 dtk, badan permintaan maks. 4,5 MB (impor CGM dibatasi 4 MB), cron sekali sehari, pratinjau dilindungi Vercel Authentication (produksi publik).
2. **Neon Free**: 1 GB penyimpanan dan 100 CU-jam per bulan per proyek; komputasi tidur saat diam sehingga permintaan pertama lebih lambat. Ukuran DB saat ini 28 MB (12 Nov 2026).
3. **Pembatas laju per instance**: login dan aksi komunitas dibatasi per instance, bukan global. Untuk pilot kecil ini cukup; untuk publik luas pindahkan ke Redis.
4. **WebSocket**: koneksi diputus paling lambat saat batas durasi fungsi; aplikasi menyambung ulang. Tanpa `REALTIME_REDIS_URL`, peristiwa dari instance lain tidak sampai lewat WebSocket (kotak masuk tetap benar lewat HTTP).
5. **Edukasi**: `EDUCATION_INCLUDE_DRAFTS=false` di produksi, jadi daftar modul kosong sampai klinisi meninjau (lihat runbook).
6. **Model foto hidangan (Modal)** dan pencarian web (Firecrawl/Brave) tidak dipasang di produksi.

## 7. Insiden saat penyiapan

Saat migrasi pertama, berkas env dibaca dengan `source` dan URL Neon yang memuat `&` terpotong; bash mencetak potongan URL, termasuk kata sandi role `neondb_owner`, ke log sesi kerja. Kata sandi langsung dirotasi lewat Neon API (12 Nov 2026), berkas ditulis ulang dengan kutip, dan migrasi dijalankan lewat pembungkus yang menyensor nilai rahasia. Basis data saat itu masih kosong.

## 8. Rollback

- Kode: `vercel rollback` (kembali ke deployment produksi sebelumnya) atau promosikan deployment lama dari dasbor.
- Data: buat branch Neon sebelum migrasi berisiko (`neon branches create --project-id <id> --name pra-migrasi`).
- Kembali ke VPS: `compose.prod.yaml` tidak berubah; set ulang `*_WORKER_ENABLED=true`.

## 9. Insiden build Git (12 Nov 2026)

Push `cf4925a` ke `main` memicu build produksi dari GitHub yang gagal: `bun install` → `Bun could not find a package.json`. Penyebab: `vercel link` (12 Nov) otomatis menyambungkan repo GitHub, tetapi Root Directory proyek kosong, jadi build berangkat dari root repo yang tidak punya `package.json`. Deploy CLI sebelumnya lolos karena diunggah dari dalam `server/`.

Perbaikan: Root Directory diatur ke `server` lewat API Vercel (`PATCH /v9/projects/beokay-api`); penautan CLI dipindah ke root; `.vercelignore` root ditambahkan. Setelah itu build lolos tetapi fungsi crash `Cannot find package '@better-auth/telemetry'` karena tata letak fungsi menjadi `/var/task/server/` dan pola `includeFiles` lama tidak cocok; pola diganti dengan alternatif `{node_modules,server/node_modules}/…`. Perubahan `server/vercel.json`, `.vercelignore`, dan `.gitignore` harus di-commit agar build Git berikutnya memakai pola yang benar; sebelum itu, build Git dari `cf4925a` menghasilkan fungsi yang crash.

## 10. Publikasi APK

APK diterbitkan sebagai situs statis di proyek Vercel **terpisah** `beokay-app` (`https://beokay-app.vercel.app/beokay.apk`), dideploy dari folder **di luar repo** supaya penautan CLI tidak menyambungkan Git (yang akan menerbitkan isi repo sebagai situs statis). Proyek `beokay-app` sengaja tanpa tautan Git dan tanpa Root Directory.

Build (kunci rilis ada di `~/beokay-release.jks`, kata sandi di `app/android/key.properties`; keduanya di luar git, **cadangkan**: tanpa kunci ini APK baru tidak bisa memperbarui yang sudah terpasang):

```bash
cd app && flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://beokay-api.vercel.app
# hasil: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (34 MB), armeabi-v7a, x86_64
```

Terbitkan (folder sementara, mis. di scratchpad):

```bash
mkdir -p /tmp/apk-site && cd /tmp/apk-site
cp <repo>/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk beokay.apk
# vercel.json: header Content-Type application/vnd.android.package-archive + Content-Disposition attachment untuk /*.apk
# index.html: halaman unduh dengan versi, ukuran, dan SHA-256
vercel link --yes --project beokay-app && vercel deploy --prod --yes
sha256sum beokay.apk   # perbarui nilai di index.html dan README bagian "Unduh aplikasi Android"
```

Batas: berkas statis Vercel Hobby maksimal 100 MB per berkas (APK arm64 34 MB). Versi 1.0.0 (`versionCode` 2001 untuk arm64) diverifikasi dengan `apksigner` (skema v2) dan memuat URL API produksi.

## 11. Upstash (Redis dan QStash)

Dibuat lewat Upstash Developer API (HTTP Basic: email akun Upstash + API key; tersimpan di `.env.deploy` sebagai `UPSTASH_EMAIL`, `UPSTASH_API_KEY`). Nilai turunannya di berkas yang sama: `REALTIME_REDIS_URL`, `UPSTASH_REDIS_ID`, `QSTASH_TOKEN`, `QSTASH_REGION` (`eu-central-1`).

- **Redis `beokay-realtime`**: dipakai hanya untuk pub/sub `beokay:realtime` (`realtime.connectBus`). Pesan membawa id instance pengirim sehingga instance tidak memutar ulang pesannya sendiri. Diuji di produksi 12 Nov 2026: klien WebSocket nyata menerima pesan yang dipublikasikan dari Redis eksternal; PING ±300 ms dari mesin pengembangan. Catatan kuota: setiap publish menghitung satu perintah dari 500 ribu per bulan.
- **QStash jadwal `beokay-jobs-tick`**: `POST https://qstash-eu-central-1.upstash.io/v2/schedules/https://beokay-api.vercel.app/internal/jobs/tick` dengan header `Upstash-Cron: */5 * * * *`, `Upstash-Method: GET`, `Upstash-Forward-Authorization: Bearer <CRON_SECRET>`, `Upstash-Schedule-Id: beokay-jobs-tick`, `Upstash-Retries: 0`, `Upstash-Timeout: 30s`. Tick bersifat idempoten (kunci `job_runs`), jadi berjalan bersama penjadwal GitHub Actions tidak menggandakan pekerjaan. Mengganti `CRON_SECRET` berarti membuat ulang jadwal dengan Schedule-Id yang sama (memperbarui jadwal yang ada) dan memperbarui secret GitHub.
- Cek jadwal: `GET https://qstash-eu-central-1.upstash.io/v2/schedules/beokay-jobs-tick` dengan `Authorization: Bearer $QSTASH_TOKEN`.
- API key Upstash sempat dibagikan di percakapan sesi kerja; bila dianggap bocor, buat ulang di Console → Account → Developer API dan perbarui `.env.deploy`.

