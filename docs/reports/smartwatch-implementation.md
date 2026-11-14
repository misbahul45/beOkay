# Laporan implementasi integrasi jam tangan

Tanggal: 14 November 2026. Tidak ada commit. Tidak ada jam tangan fisik.

## A. Ringkasan

beOkay kini punya jalur data wearable berbasis Health Connect: pembacaan satu adapter, normalisasi, sinkron dengan kursor dan outbox, detak jantung (bucket 5 menit) dan detak jantung istirahat, status koneksi yang memisahkan izin/sinkron/kesegaran/asal data, layar Perangkat & Kesehatan, layar Detak jantung, kartu Today, dan simulator tanpa perangkat. Server menegakkan consent, preferensi, idempotensi, dan penjaga simulasi.

Yang **tidak** dibuktikan: jam tangan nyata. Verifikasi tertinggi adalah emulator Android dengan Health Connect nyata dan data sintetis. Status jam tangan tertinggi yang pernah dihitung otomatis: `WATCH_SOURCE_DETECTED`, dan itu pun hanya bila metadata perangkat dari Health Connect menyatakan `watch`. Pada verifikasi ini metadata tidak menyatakannya, sehingga statusnya `WATCH_NOT_VERIFIED`.

## B. Temuan audit awal

Lihat [audit](../audits/smartwatch-integration-audit.md). Tambahan yang baru ketahuan saat uji emulator nyata (tidak terlihat oleh uji widget/mock):

1. Pembacaan `WORKOUT` lewat paket `health` **diam-diam kosong** bila izin langkah, jarak, dan kalori total tidak dipegang (paket membaca ketiganya untuk tiap sesi dan melempar `SecurityException`). Impor latihan 4.0 karenanya tidak akan pernah mengembalikan sesi di perangkat nyata. Diperbaiki: izin itu diminta bersama latihan, dan `READ_TOTAL_CALORIES_BURNED` ditambah ke manifes. Kalori tidak disimpan.
2. `HealthDataPoint.sourceId` kosong di Android; nama paket ada di `sourceName`. Provenans 4.0 (`dataOrigin`) karenanya kosong. Diperbaiki.
3. `flutter test integration_test` mencopot aplikasi setelah selesai sehingga izin hilang; gunakan `--no-uninstall` (lihat panduan uji).
4. `getTotalStepsInInterval` mengembalikan **0**, bukan `null`, untuk hari tanpa rekaman. Klien lama mengirim 0 langkah untuk semua hari kosong sehingga hari tanpa data tampak "ada data" dan kartu Langkah menulis "Median 7 hari 0". Terlihat saat aplikasi dijalankan di emulator. Diperbaiki di 1.2.1: total 0 dianggap tidak ada data dan tidak dikirim (normalizer dan adapter; ada tes). APK 1.2.0 yang sempat terbit membawa perilaku lama; baris 0 yang sudah terkirim tidak dihapus otomatis.
5. Lencana "Sinkron latar didukung" mencerminkan kemampuan Android, bukan fitur beOkay (sinkron latar belum ada). Diganti menjadi "Sinkron saat aplikasi dibuka".

## C. Arsitektur

Lihat [arsitektur](../architecture/smartwatch-integration.md).

## D. Berkas

Baru (server): `devices/{heart-rate.model,heart-rate.service,device-today.service,sync-checkpoint.service,provenance,simulation}.ts`, migrasi `20261114150000_smartwatch_integration` dan skrip turunnya, `tests/unit/smartwatch.test.ts`, `tests/integration/smartwatch.test.ts`.
Diubah (server): skema Prisma, `config/env.ts`, `devices/{device-import.*,quality.*}`, `events/record-events.ts`, `activity/activity-import.*`, `projections/daily-facts.*`, `coaching/coaching.service.ts`, `goals/goals.service.ts`, `export/{export,fhir}.service.ts`.
Baru (app): `features/devices/{data,domain,application,presentation}/*` (lihat arsitektur), `HealthMetadataBridge.kt`, `test/unit/smartwatch_core_test.dart`, `test/flows/smartwatch_test.dart`, `integration_test/smartwatch_hc_test.dart`.
Dihapus: `features/devices/data/health_signals.dart` (digantikan).
Diubah (app): manifes, `build.gradle.kts`, `MainActivity.kt`, router, pengaturan, Today, `device_activity_source.dart` (kini mendelegasikan ke adapter tunggal).
Lain: `compose.yaml`/`compose.test.yaml`/`.env.example` (`DEVICE_SIMULATION_ENABLED`), koleksi Bruno `21 - Smartwatch Integration`, lima dokumen ini.

## E. Basis data

Migrasi aditif `20261114150000_smartwatch_integration`: `wearable_heart_rate_buckets`, `wearable_resting_heart_rates`, `device_sync_checkpoints`; kolom `heart_rate`, `resting_heart_rate` pada `device_import_preferences`; `recording_method`, `device_type`, `updated_at` pada `sleep_sessions`; CHECK sumber `simulated` pada `daily_steps`, `sleep_sessions`, `activity_sessions`. Skrip turun: `server/prisma/rollback/20261114150000_smartwatch_integration.down.sql`. `prisma migrate diff` setelah migrasi hanya menyisakan noise yang tercatat di AGENTS.md. Diterapkan ke Neon produksi setelah membuat cabang cadangan `pre-smartwatch-20261114` (tanpa compute).

## F. API

Lihat [API](../api/smartwatch-integration.md). Perubahan kompatibel mundur: klien 1.1.2 tanpa bidang baru tetap dilayani (diuji).

## G. Flutter

Satu adapter `HealthConnectDataSource` (dan `SimulatedHealthDataSource`) memberi makan satu `HealthNormalizer` dan satu `SyncCoordinator`. UI mengikuti gaya yang ada (`SoftCard`, `SettingsGroup`, `PillButton`); desain figcraft tidak dibuat karena figcraft gagal terhubung dan pengguna mengizinkan UI tanpa figcraft.

## H. Simulasi

Lihat [panduan uji](../testing/smartwatch-simulation.md).

## I. Verifikasi (perintah yang dijalankan dan hasil nyata)

| Pemeriksaan | Hasil |
|---|---|
| `bun run typecheck` (Docker) | bersih |
| `bun test` penuh (Docker, DB uji terisolasi) | **480 lulus, 0 gagal, 83 berkas** (17 tes baru) |
| Bruno `21 - Smartwatch Integration` | **15/15** lulus |
| `flutter analyze` | bersih |
| `flutter test` penuh | **290 lulus, 0 gagal** (40 tes baru: 25 unit, 15 widget) |
| Emulator, Health Connect nyata: fase `connect` | lulus: langkah hari ini 5.500 dan kemarin 7.300, detak jantung 40 sampel → 9 bucket (terbaru 72 bpm), istirahat 59, tidur 2 sesi, latihan 2 (1 dibuat + 1 perlu ditinjau karena tumpang tindih), asal data `dev.scratch.hcwriter`; sinkron ulang: semua hitungan identik (tidak ada duplikat) |
| Emulator, fase `revoked` (izin detak jantung dicabut dengan `pm revoke`) | lulus: pesan "Detak jantung: Izin Health Connect belum diberikan", keadaan `syncFailed`, server `SYNC_FAILED`/`PERMISSION_DENIED`, data lama tidak berubah |
| Emulator, fase `recovered` (izin diberikan lagi) | lulus: keadaan kembali `dataAvailable`, `syncState OK`, hitungan data tidak berubah |
| Migrasi produksi | `Database schema is up to date!` (35 migrasi); cabang cadangan Neon `pre-smartwatch-20261114` dibuat lebih dulu |
| APK rilis 1.2.0 | ditandatangani `CN=beOkay`, `versionCode` 2005, URL API produksi tertanam, peluncuran di emulator tanpa crash; terbit di `beokay-app`; digantikan 1.2.1 (lihat bawah) |
| APK rilis 1.2.1 | memperbaiki langkah 0 untuk hari tanpa data dan lencana sinkron latar; `versionCode` 2006, penanda tangan sama (`3dd5f626…d629`), SHA-256 `3b20540f…a7be`, terbit di `beokay-app` |
| Deploy API + landing | `vercel deploy --prod` dari root: status Ready, alias `beokay-api.vercel.app`, fungsi di `sin1`; `/health` `db: true`; `/api/me/heart-rate`, `/api/me/devices/today`, `/api/me/device-sync/checkpoints`, `/api/me/device-import/preferences` tanpa sesi → 401; bundel landing memuat teks baru dan SHA APK baru; `DEVICE_SIMULATION_ENABLED` tidak ada di env produksi |
| Produksi dengan sesi pengguna | **tidak diverifikasi**: membuat sesi sintetis langsung di DB produksi diblokir pengaman, dan tidak dicari jalan lain. Penolakan sumber simulasi pada konfigurasi produksi diuji lewat `TEST-20` dan tes unit penjaga (`NODE_ENV=production` selalu menolak), bukan lewat panggilan produksi |

## J. Batasan yang tersisa

Memerlukan jam tangan nyata dan aplikasi pendampingnya: pembuktian bahwa `Device.type = watch` benar-benar dikirim vendor, urutan sinkron vendor (mis. Samsung Health baru mengirim saat jam tangan terhubung), dan perilaku revisi tidur vendor.
Belum diimplementasikan: sinkron latar (WorkManager, izin latar), rekonsiliasi penghapusan di sumber, `lastModifiedTime`, izin riwayat >30 hari, perangkat kelas rendah dan TalkBack (`UNVERIFIED`), HRV/SpO2/energi aktif (dinyatakan tidak didukung). Toolbox resmi dipasang tetapi pengisian rekaman memakai aplikasi penulis sementara.
Perangkat fisik Android: tidak diuji.

## K. Kesiapan

| Tingkat | Status |
|---|---|
| Code Ready | ya (server dan app) |
| Tests Passed | ya (angka di bagian I) |
| Emulator Verified | ya, Health Connect nyata, data sintetis |
| Physical Device Verified | **tidak** |
| Production Ready | server dan APK 1.2.0 sudah diterbitkan; **belum** layak untuk klaim "mendukung jam tangan" (tidak ada uji perangkat fisik, tidak ada verifikasi produksi dengan sesi pengguna). Landing menyatakan "diuji di emulator, belum di jam tangan nyata" |
