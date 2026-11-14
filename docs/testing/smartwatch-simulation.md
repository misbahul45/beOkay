# Menguji integrasi jam tangan tanpa jam tangan

Tidak ada jam tangan yang dipakai di sini. Semua cara di bawah memakai data sintetis dan **tidak** membuktikan jam tangan terpasang.

## Mode A: sumber simulasi (tanpa perangkat)

`SimulatedHealthDataSource` mengisi jalur yang sama (normalizer → koordinator → API → DB). Hanya di build debug, atau rilis dengan `--dart-define=BEOKAY_SIMULATION=true`, dan server wajib `DEVICE_SIMULATION_ENABLED=true` di luar produksi.

1. Jalankan stack dev: `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose up -d --build` (dev menyalakan simulasi bawaan).
2. `adb reverse tcp:3000 tcp:3000`, jalankan aplikasi debug, buka Pengaturan → Perangkat & Kesehatan.
3. Di bagian "Mode simulasi", pilih profil. Banner **DATA SIMULASI** muncul.
4. Nyalakan jenis data, tekan "Sinkronkan sekarang".

Profil: `activeDay`, `lowActivityDay`, `noDataDay`, `partialDay`, `multipleSources`, `conflictingSources`, `staleMeasurements`, `permissionRevoked`, `offlineSynchronization` (data seperti `activeDay`; pasangkan dengan klien tanpa jaringan). Keluaran deterministik untuk jam yang sama. Berat dan glukosa simulasi hanya ada untuk uji normalisasi dan tidak pernah dikirim.

Produksi menolak: `POST /api/me/device-import` dengan `source: simulated` → `403 SIMULATION_DISABLED`, meski `DEVICE_SIMULATION_ENABLED` diisi (diuji sebagai `TEST-20`).

## Mode B: Health Connect nyata di emulator

Menjalankan jalur platform sesungguhnya (izin Health Connect, pembacaan, metadata) dengan data sintetis dari aplikasi lain.

1. Emulator Android 14+ (Health Connect bawaan). Dipakai: `Pixel_4`, image `google_apis_playstore_ps16k`, Android 37.1. Cek: `adb shell pm list packages | grep healthconnect`.
2. Toolbox resmi: unduh dari tautan di [panduan Google](https://developer.android.com/health-and-fitness/health-connect/test/health-connect-toolbox) (`https://goo.gle/health-connect-toolbox`, ZIP berisi APK), lalu `adb install HealthConnectToolbox-<versi>.apk`.
3. Di Toolbox: izinkan "tampil di atas aplikasi lain", beri izin tulis, lalu **Insert Health Record** untuk: Steps (interval), Heart rate (sampel), Resting heart rate, Sleep session, Exercise session. Catat UUID tiap rekaman bila ingin memperbarui.
4. Beri izin baca ke beOkay di Health Connect (atau `adb shell pm grant id.beokay.app android.permission.health.READ_HEART_RATE`, dan seterusnya untuk `READ_STEPS`, `READ_RESTING_HEART_RATE`, `READ_SLEEP`, `READ_EXERCISE`, `READ_DISTANCE`).
5. Di beOkay: nyalakan jenis data lalu "Sinkronkan sekarang". Ulangi sinkron; jumlah tidak boleh bertambah.
6. Cabut izin (`adb shell pm revoke ...` atau dari Health Connect), sinkronkan: harus muncul "Izin Health Connect belum diberikan" dan status server `permissionState`. Beri izin lagi, sinkronkan: data pulih.

Alat bantu otomatis yang dipakai pada verifikasi ini: `app/integration_test/smartwatch_hc_test.dart` (UI nyata, Health Connect nyata, API dev nyata). Catatan penting: sumber data sintetis di emulator ini tidak mengisi `Device.type`, jadi `watchVerification` tetap `WATCH_NOT_VERIFIED`. Itu perilaku yang benar.

```bash
flutter test integration_test/smartwatch_hc_test.dart -d emulator-5554 \
  --dart-define=E2E_TOKEN=<token sesi akun uji dev> --dart-define=E2E_PHASE=connect
```

Fase: `connect` (nyalakan, sinkron, sinkron ulang tanpa duplikat), `revoked`, `recovered`.

Urutan penuh yang dijalankan (akun sintetis baru di DB dev):

```bash
cd app && flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
for p in STEPS HEART_RATE RESTING_HEART_RATE SLEEP EXERCISE DISTANCE TOTAL_CALORIES_BURNED; do
  adb shell pm grant id.beokay.app android.permission.health.READ_$p; done
flutter test integration_test/smartwatch_hc_test.dart -d emulator-5554 --no-uninstall \
  --dart-define=E2E_TOKEN=$TOKEN --dart-define=E2E_PHASE=connect
adb shell pm revoke id.beokay.app android.permission.health.READ_HEART_RATE   # lalu E2E_PHASE=revoked
adb shell pm grant  id.beokay.app android.permission.health.READ_HEART_RATE   # lalu E2E_PHASE=recovered
```

`--no-uninstall` wajib: tanpa itu `flutter test` mencopot aplikasi setelah selesai dan izin hilang. Izin dipasang lewat `pm grant` sebelum tes karena dialog izin sistem tidak bisa diklik dari dalam tes. Token berasal dari akun sintetis di DB dev; jangan memakai akun produksi.

Bukan Toolbox: pada verifikasi ini rekaman dibuat oleh aplikasi penulis sementara (di luar repositori) lewat paket `health` karena Toolbox hanya berinteraksi lewat UI hamparan. Langkah Toolbox di atas adalah prosedur yang direkomendasikan untuk pengembang; langkah itu **belum dijalankan** dalam verifikasi ini.

## Mode C: emulator Wear OS (opsional)

Tidak dibuat. Emulator Wear OS tidak otomatis mengisi penyimpanan Health Connect ponsel; perlu aplikasi pendamping atau jembatan data yang di luar cakupan. Toolbox sudah mencakup kontrak integrasi.

## Pengujian otomatis

| Lapisan | Perintah | Cakupan |
|---|---|---|
| Server (Docker) | `docker compose -f compose.test.yaml run --rm tester bun test` | 17 tes baru: model, provenans, penjaga simulasi, TEST-01…20 |
| Bruno | `bru run "21 - Smartwatch Integration" --env test` (container Node di jaringan `beokay-test_default`) | 15 permintaan |
| Flutter (host) | `flutter analyze` dan `flutter test` | tes unit (normalizer, simulasi, mesin keadaan, penyimpanan, koordinator) dan tes widget (layar perangkat, detak jantung, kartu Today, teks besar, mode gelap) |
| Emulator | perintah di atas | fase connect/revoked/recovered |

Matriks TEST-01…20 ada di `server/tests/integration/smartwatch.test.ts`. TEST-15 (penghapusan sumber) **tidak diimplementasikan**.
