# beOkay 3.0 — Fase 9: Sinyal perangkat dan operasi

> Tanggal: 12 November 2026. Cakupan dari [gap analysis §8](../audits/gap-analysis-2026-11-12.md): K-1, S-1, S-6, S-7/K-9, U-3, U-8, S-8, S-10.
> Desain FigCraft: halaman "30 — Fase 9: Sinyal perangkat dan operasi" di `design/beOkay-ui-v3.figcraft`, ekspor `design/exports/30-*.png`. Halaman "29 — Fase 8" juga dibuat di sesi ini. Keduanya dibuat lewat MCP FigCraft headless (`figcraft-cli mcp`) **setelah** kodenya ditulis, karena MCP `figcraft` aplikasi tidak tersambung di awal sesi.

## 1. Ringkasan

| Butir | Hasil | Status |
|---|---|---|
| K-1 Health Connect | langkah harian, berat, glukosa alat, tidur; satu sakelar dan satu izin per jenis; tujuan `daily_steps`; kartu Langkah di Beranda | **selesai**; pembacaan Health Connect sungguhan belum diuji di ponsel |
| S-1 metrik dan alarm | `GET /metrics` Prometheus, `check-alarms.ts` + surel | **selesai**; cron belum dipasang |
| S-6 kunci aplikasi | biometrik/PIN perangkat saat membuka (setelah 60 dtk di latar) dan sebelum ekspor/hapus akun | **selesai** |
| S-7/K-9 ringkasan dan tautan | PDF dibuat di perangkat; tautan baca-saja berbatas waktu + kode QR; dicabut kapan saja | **selesai** |
| U-3 aksesibilitas | pengumuman pembaca layar untuk notifikasi baru, status sinkron, hasil simpan; palet kontras tinggi; `liveRegion` | **sebagian**: uji TalkBack manual 6 alur belum dilakukan |
| U-8 aksi notifikasi | "Sudah"/"Nanti" pada pengingat obat; pintasan peluncur; widget 1×1 "Catat" | **selesai**; ketukan aksi di perangkat sungguhan belum diuji |
| S-8 E2E | 3 alur `integration_test` (masuk, glukosa luring → sinkron, kotak masuk) lulus di emulator; job CI `app-e2e` | **selesai**; CI belum pernah jalan di GitHub |
| S-10 keamanan | sapuan IDOR otomatis untuk semua rute GET ber-parameter, sapuan 401 semua `/api/me/*`, masukan tidak wajar, header keamanan, ZAP baseline 0 gagal, contoh proxy | **selesai** |

Kriteria terima fase: (1) langkah harian dari Health Connect masuk tujuan dan JITAI: **terpenuhi di server** (tujuan `daily_steps` dihitung dari `daily_steps`, dan pemicu JITAI `GOAL_WINDOW_APPROACHING` memakai tujuan aktif apa pun); (2) PDF ringkasan: **terpenuhi**; (3) TalkBack lulus 6 alur: **belum**, butuh uji manual di ponsel; (4) CI hijau dengan E2E: **job ditulis dan alurnya lulus lokal di emulator**, belum dijalankan GitHub.

## 2. Sinyal perangkat (K-1)

- `device_import_preferences`: lima sakelar, semuanya mati secara bawaan. Server menolak jenis yang dimatikan (`DEVICE_TYPE_DISABLED`); aplikasi meminta izin Health Connect hanya untuk jenis yang dinyalakan, dan manifes menambah `READ_WEIGHT`, `READ_BLOOD_GLUCOSE`, `READ_SLEEP`.
- Langkah: agregat harian dari `getTotalStepsInInterval`, satu baris per tanggal lokal, diganti nilai terbaru (`upserted`/`unchanged`), tanggal di masa depan ditolak.
- Berat → `vital_measurements` (`source=health_connect`, `external_id` unik). Glukosa → `glucose_observations` (`source=health_connect`, `device_reported`, satuan asli dipertahankan). Glukosa perangkat ikut dihitung di ringkasan harian, statistik, tren, dan konteks Fase 8 (konstanta `GLUCOSE_COUNTED_QUALITY`). Koreksi catatan perangkat tidak bisa mengubahnya menjadi "dilaporkan sendiri".
- Tidur: hanya awal, akhir, durasi.
- Tujuan `daily_steps` (`SUM_DEVICE_STEPS`); refleksi menawarkan penyesuaian dari persentil ke-60 10 hari, naik ≤ 10% bila ≥ 60% hari tercapai, turun ≤ 10% bila persentil < 60% target.

## 3. Operasi (S-1, S-10)

- `/metrics`: penghitung permintaan per rute yang dinormalisasi (ID diganti `:id`, token `/s/:token`), histogram latensi, semua `logEvent` sebagai `beokay_log_events_total{level,event}` (kegagalan LLM/Modal/push otomatis terhitung), status outbox, push 24 jam, notifikasi belum dibaca, laporan kejadian yang belum terkirim, status sakelar fitur, `database_up`. Di `production` butuh `METRICS_TOKEN`.
- `check-alarms.ts`: p95 > 800 ms, outbox `DEAD` > 0, push gagal > 5% (≥ 20 pengiriman), laporan kejadian belum terkirim → JSON + kode keluar 1 + surel `ALERT_EMAIL_TO`.
- Header: CSP di semua balasan (API `default-src 'none'`; halaman baca-saja memakai nonce gaya per permintaan), `Cross-Origin-Resource-Policy`, `Permissions-Policy`, `no-store` di semua balasan, HSTS di `production`. Contoh Caddy/nginx di [reverse-proxy.md](../operations/reverse-proxy.md).
- Tabel rute dipindah ke `src/routes.ts` agar tes bisa menyapu semuanya. Sapuan IDOR memakai ID nyata milik pengguna A (glukosa, makan, aktivitas, vital, lab, tujuan, obat, pengingat, tautan, percakapan) pada setiap rute GET ber-parameter sebagai pengguna B: tidak ada 2xx, tidak ada 5xx, ID pemilik tidak bocor. Sapuan tanpa login: setiap metode setiap rute `/api/me/*` membalas 401 dengan header keamanan.
- ZAP baseline (`ghcr.io/zaproxy/zaproxy:stable`) pada `/health`, `/s/<token>`, `/api/me/today`: 67 lulus, 0 gagal, satu peringatan informasional "Non-Storable Content" yang memang disengaja.

## 4. Ringkasan untuk kontrol (S-7/K-9)

- `GET /api/me/report-summary` menjadi satu sumber untuk PDF di perangkat dan halaman baca-saja: statistik `stats-v1` yang siap, langkah, ukuran dan lab terakhir, obat aktif, catatan "bukan diagnosis".
- PDF dibuat di perangkat (`pdf`, huruf Inter yang dibundel) lalu dibagikan; server tidak menyimpan berkas.
- Tautan: konfirmasi wajib (`confirm: true` + dialog), 1–7 hari, maksimal 5 aktif, token 256 bit yang hanya disimpan sebagai hash, `noindex`, akses dihitung dan diaudit, mati bila consent ringkasan ditarik. Aplikasi menampilkan kode QR, salin/bagikan, dan daftar tautan aktif dengan tombol Cabut.

## 5. Aplikasi (S-6, U-3, U-8)

- Kunci aplikasi (`local_auth`, PIN/biometrik perangkat): disimpan per akun di penyimpanan aman; terkunci saat dibuka dingin dan setelah ≥ 60 dtk di latar; ekspor dan hapus akun meminta verifikasi ulang.
- Pengumuman pembaca layar: notifikasi baru, "Semua catatan sudah terkirim", "N catatan perlu ditinjau", hasil simpan form, hasil catat cepat, hasil sinkron perangkat, tautan dibuat/dicabut. Baris status sinkron adalah `liveRegion`. Palet kontras tinggi dipakai bila sistem meminta (teks sekunder = teks utama).
- Aksi notifikasi: kejadian obat 2 hari ke depan dijadwalkan sebagai notifikasi lokal dengan aksi "Sudah" (membuka aplikasi lalu mencatat jadwal tepat itu sebagai diminum, antrean luring bila perlu) dan "Nanti" (menutup). Teks layar kunci tidak memuat nama obat. Pintasan peluncur: Catat cepat, Catat glukosa, Catat makan (`beokay://app/...`). Widget 1×1 membuka lembar Catat.

## 6. Pengujian

| Lapisan | Hasil |
|---|---|
| Backend `bun test` | **359/359** (67 berkas); baru `tests/unit/phase9.test.ts` (4) dan `tests/integration/phase9.test.ts` (6) |
| `tsc --noEmit` | bersih |
| `prisma migrate diff` | hanya drift lama dan noise yang diizinkan |
| Flutter | `flutter analyze` bersih; **224/224**; baru `test/flows/phase9_test.dart` (6) |
| E2E `integration_test` di emulator Pixel_4 (Android API 37) | **3/3**; APK debug dengan widget, pintasan, dan izin baru berhasil dibangun |
| ZAP baseline | 0 gagal |

Tidak diverifikasi: data Health Connect sungguhan, biometrik di ponsel, ketukan aksi notifikasi di perangkat, TalkBack manual, CI GitHub.

## 7. Yang harus dilakukan pemilik

1. Isi `METRICS_TOKEN`, `ALERT_EMAIL_TO`, dan (bila domain publik berbeda) `PUBLIC_BASE_URL`; pasang cron `check-alarms.ts`.
2. Uji TalkBack 6 alur dan Health Connect di ponsel nyata.
3. Push ke GitHub agar job `backend`, `app`, dan `app-e2e` berjalan.

## 8. Rollback

Migrasi `20261112120000_p9_devices_ops` menambah tabel dan memperluas CHECK; data perangkat bisa dihapus per tabel. Menonaktifkan tanpa rollback: matikan sakelar perangkat di aplikasi, cabut tautan, kosongkan `METRICS_TOKEN` (endpoint jadi 404 di prod).
