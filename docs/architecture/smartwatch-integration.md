# Arsitektur integrasi jam tangan

Status: kode selesai dan diuji di tingkat unit, integrasi, dan emulator dengan data sintetis. **Belum diuji dengan jam tangan nyata.** Lihat [laporan](../reports/smartwatch-implementation.md).

## 1. Prinsip

1. Health Connect adalah satu-satunya gerbang data Android. beOkay hanya membaca.
2. Jam tangan dipasangkan lewat aplikasi pendampingnya. Data di Health Connect **tidak membuktikan** adanya jam tangan.
3. Tiga lapis otorisasi independen: izin Health Connect, preferensi impor beOkay per jenis (semua mati bawaan), consent `health_data_processing`. Saran personal memerlukan `device_data_coaching` tambahan.
4. Server menegakkan autentikasi dan consent sendiri; Flutter hanya antarmuka.
5. Data simulasi selalu berlabel dan tidak pernah masuk proyeksi, saran, skor, atau ekspor FHIR.
6. Data hilang adalah `null`/`NO_DATA`, bukan nol, dan bukan "tidak aktif".

## 2. Alur data

```text
Jam tangan → aplikasi vendor → Health Connect
   → HealthConnectDataSource (paket health + jembatan Kotlin metadata perangkat)
   → HealthNormalizer (satuan, bucket 5 menit, validasi)
   → SyncCoordinator (mutex, jendela, batch, kursor, outbox)
   → DeviceImportRepository → POST /api/me/device-import | /api/me/activities/import
   → autentikasi + consent + preferensi → transaksi DB → emitRecordEvent
   → proyeksi harian | status perangkat | Today | Detak jantung
```

Jalur simulasi memakai komponen yang sama mulai dari `HealthNormalizer`; hanya sumbernya (`SimulatedHealthDataSource`) dan nilai `source: "simulated"` yang berbeda.

## 3. Klien

`app/lib/features/devices/`:

| Lapisan | Berkas | Peran |
|---|---|---|
| data | `health_source.dart` | antarmuka `HealthDataSource`, `RawMeasurement`, kapabilitas |
| data | `health_connect_source.dart` | adapter nyata, `openHealthConnectSettings`, kanal metadata |
| data | `simulated_source.dart` | sembilan profil deterministik |
| data | `device_import_repository.dart` | API, batas batch per metrik |
| domain | `normalizer.dart`, `measurements.dart` | normalisasi dan bucket |
| domain | `connection_state.dart` | mesin keadaan koneksi |
| domain | `device_status.dart`, `heart_rate.dart` | model respons |
| application | `sync_coordinator.dart`, `sync_store.dart` | sinkron, kursor, outbox |
| application | `devices_controller.dart` | provider, pengendali koneksi, sinkron otomatis |
| presentation | `devices_screen.dart`, `heart_rate_screen.dart`, `wearable_today_card.dart`, `simulation_panel.dart` | UI |

Android: `HealthMetadataBridge.kt` (kanal `beokay/health_metadata`) membaca `metadata.device` (tipe, pabrikan, model) per `recordId` dan membuka pengaturan Health Connect. Tanpa jembatan ini paket `health` hanya memberi nama paket dan metode perekaman.

### Keadaan koneksi

`platformUnavailable`, `healthConnectUnavailable`, `notAuthorized`, `authorizedNoData`, `dataAvailable`, `syncing`, `syncFailed`, `syncStale`, `importDisabled`. Status jam tangan dipisah: `notVerified`, `sourceDetected` (server melihat `deviceType = watch` dari sumber nyata), `hardwareVerified` (tidak pernah dihitung otomatis).

### Sinkronisasi

- Pemicu: koneksi awal, manual, aplikasi kembali ke depan (minimal 5 menit antar), timer 15 menit saat aplikasi aktif, jaringan pulih. Backoff eksponensial setelah gagal (maks. 60 menit). Satu sinkron berjalan sekaligus (panggilan bersamaan digabung).
- Jendela: pertama dan manual membaca 14 hari. Inkremental membaca dari kursor terkecil dikurangi 24 jam, disejajarkan ke 5 menit; langkah minimal 3 hari. Tanpa izin riwayat, Health Connect membatasi 30 hari.
- Kursor per (akun, sumber, metrik) hanya maju setelah server menerima semua batch metrik itu.
- Outbox: batch yang gagal karena jaringan disimpan terenkripsi (`flutter_secure_storage`), maksimal 24 entri, dikuras sebelum sinkron berikutnya; consent ditarik menghapusnya; kunci per akun.
- Metrik berat dan glukosa tidak pernah dikirim dari sumber simulasi.

## 4. Server

`server/src/features/devices/`: `device-import.*` (impor), `heart-rate.model.ts` dan `heart-rate.service.ts`, `device-today.service.ts`, `sync-checkpoint.service.ts`, `quality.*`, `provenance.ts`, `simulation.ts`.

### Model detak jantung

Sampel dikelompokkan klien menjadi jendela 5 menit sejajar epoch UTC: `bpm_min`, `bpm_max`, `bpm_avg` (rata-rata sampel, bukan berbobot waktu), `sample_count`. Tabel `wearable_heart_rate_buckets` unik per (pengguna, sumber, asal data, awal jendela). Alasan: sampel mentah per detik/menit membengkakkan basis data (Neon free) tanpa nilai tambah untuk ringkasan; aturan agregasi eksplisit dan tidak ada interpolasi.

Aturan revisi bucket: jendela baru dengan `sample_count` lebih besar memperbarui; lebih kecil dianggap revisi lebih lama dan dipertahankan (`UNCHANGED`, `OLDER_REVISION`). Detak jantung istirahat: `wearable_resting_heart_rates` per `externalId`.

Domain teknis 20–300 bpm; di luar itu ditolak per rekaman. Di bawah 30 atau di atas 220 (istirahat: 30–140) hanya diberi bendera `UNUSUAL_VALUE` dan status `needs_review`. Tidak ada diagnosis.

### Proyeksi

Detak jantung **tidak** masuk `daily_behavior_facts` dan tidak masuk saran atau skor (`heartRate` sudah ada di `FORBIDDEN_RANKING_INPUTS`). Alasan: menghindari penghitungan ulang global dan menjaga batas "tanpa klaim klinis". Yang berubah di proyeksi: `daily-facts-v2` menghitung `recordingMethod=manual` sebagai manual, dan semua sumber `simulated` dikecualikan.

### Simulasi

`source: "simulated"` diterima hanya bila `DEVICE_SIMULATION_ENABLED=true` **dan** `NODE_ENV != production`; selain itu `403 SIMULATION_DISABLED`. Dibatasi ke langkah, tidur, sesi olahraga, detak jantung; berat dan glukosa simulasi ditolak (`SIMULATED_NOT_SUPPORTED`). Baris simulasi dikecualikan dari proyeksi, tujuan, koreksi, dan FHIR, tetapi tampil di layar perangkat dengan lencana **DATA SIMULASI**.

## 5. Batasan yang diketahui

- Tidak ada sinkron latar (WorkManager) dan tidak ada izin latar/riwayat di manifes.
- Penghapusan rekaman di sumber tidak disinkronkan; rekaman tidak dihapus tanpa kebijakan.
- Tidak ada `lastModifiedTime`; revisi tidur dideteksi dari perbedaan waktu.
- Langkah agregat tidak punya asal data per jam tangan; hari langkah memakai zona waktu ponsel.
- Energi aktif, saturasi oksigen, dan HRV **tidak** didukung (dikembalikan sebagai tidak didukung di UI).
- Data lebih lama dari jendela tumpang 24 jam yang baru dikirim sumber belakangan terlewat sampai sinkron manual 14 hari.
