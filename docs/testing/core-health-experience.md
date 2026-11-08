# Verifikasi Core Health — Slice 1

Pembaruan Slice 3: [pengujian Glucose](glucose.md) mencatat hasil terbaru backend, Flutter, Bruno dan Appium. Angka Slice 1–2 di bawah dipertahankan sebagai bukti historis. Semua backend test/migration/typecheck tetap dalam Docker dengan database terisolasi.

Pembaruan Slice 2: [verifikasi Nutrition](nutrition.md) mencatat backend 6 tes/106 assertion, Flutter 33 tes, Bruno 19 request dan 12 skenario Appium. Bagian Slice 1 di bawah adalah histori verifikasi fondasi.

Pembaruan 8 November 2026: [pengujian Appium Today](today-appium.md) sudah dijalankan terhadap API/PostgreSQL nyata, dengan 13 skenario terverifikasi dan screenshot perangkat. Batas cakupan dan perbedaannya dari tes widget tercatat pada laporan tersebut.

Backend wajib Docker; Flutter/Dart di host sesuai AGENTS.md. Jangan jalankan suite pada database produksi/dev. `compose.test.yaml` memakai PostgreSQL tmpfs dan Mailpit terpisah, tanpa port publik.

```bash
docker compose -f compose.test.yaml up -d --wait api-test
docker compose -f compose.test.yaml run --rm tester bun test
docker compose -f compose.test.yaml exec -T api-test bun run typecheck
```

Jika sumber API berubah setelah container start: restart `api-test`, karena command test bukan hot reload. Tes membuat akun sintetis dengan password random. Cleanup seluruh fixture dan email lewat `docker compose -f compose.test.yaml down -v` setelah verifikasi. Tidak menyentuh volume dev.

```bash
cd app
flutter test
flutter analyze
flutter build apk --debug --no-pub
```

Red backend: route belum ada → 404 vs 401, modul today.model belum ada. Red Flutter: file Today belum ada. Green: unit tanggal pada offset positif/negatif dan midnight; greeting lokal; nilai null dan NOT_AVAILABLE. Integrasi: register, Mailpit verify, Better Auth login, consent, profile/settings, onboarding, GET Today, query userId diabaikan, dua akun berbeda, withdrawal kedua purpose, logout/rejected session. Widget: 320 px dan text scaling 2, unavailable previews tanpa nol, network failure dan retry. Identity/widget fixtures bukan bukti E2E perangkat nyata.

Bruno ada di `docs/api/bruno`, satu collection/environment bersama. Belum ada koleksi sebelumnya dalam repository. Jalankan CLI dari root collection pada jaringan Docker `beokay-test_default`; environment `test` menggunakan `http://api-test:3000`. Berikan `sessionToken` dan `restrictedSessionToken` secara runtime (`--env-var`) dari dua akun sintetis verified; akun restricted tanpa consent. Jangan simpan token di environment tracked. Request tanpa sesi dapat dijalankan sendiri tanpa token.

```bash
bru run --env test
bru run '17 - Security and Negative Tests/Today without session.bru' --env test
```

CLI di sesi ini dijalankan dalam container Node sementara, bukan host. Fixture bootstrap sementara berada di `/tmp`, tanpa kredensial literal. Angka hasil aktual ada di `docs/reports/core-health-implementation.md`.

Visual: `SHOT_DIR=/tmp/beokay-today-review flutter test test/flows/identity_flows_test.dart --plain-name 'B. returning user with a stored session lands on home'` menghasilkan `today-foundation.png`. TestHarness memuat font Inter dan MaterialIcons untuk screenshot, sehingga bukan kotak Ahem. Pemeriksaan screenshot mencakup viewport awal; belum parity FigCraft atau audit seluruh layar/perangkat.
