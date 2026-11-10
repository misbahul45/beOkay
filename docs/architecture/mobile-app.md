# Aplikasi Mobile (Flutter)

> Diaudit 10 November 2026. Lokasi: `app/`. Target: **Android saja** (keputusan pemilik; tidak ada iOS/HealthKit). Folder `ios/`, `macos/`, `linux/`, `windows/`, `web/` ada karena `flutter create`, tetapi tidak dipakai.
> Status: `flutter analyze` → *No issues found*; `flutter test` → **157 tes lulus** (dijalankan pada audit ini).

## 1. Ringkasan teknis

| Hal | Nilai |
|---|---|
| SDK | Dart `^3.12.2`, versi aplikasi `1.0.0+1` |
| State | `flutter_riverpod ^3.5` (`Notifier`/`Provider`; `ProviderScope(retry: (_, _) => null)` — tanpa auto-retry provider) |
| Navigasi | `go_router ^18` dengan `redirect` terpusat |
| HTTP | paket `http` lewat `ApiClient` sendiri (tanpa Dio) |
| Penyimpanan | `flutter_secure_storage` (token sesi, antrean offline, status push) — Keystore Android |
| Tampilan | satu tema terang, font Inter (400/600/700), bahasa tunggal `id_ID`; **tidak ada tema gelap** |
| Perangkat | kamera + `mobile_scanner` (barcode), `image_picker`, `share_plus` + `path_provider` (ekspor), `health` (Health Connect), `flutter_local_notifications`, `firebase_messaging` |
| Konfigurasi | `AppConfig.apiBaseUrl` dari `--dart-define=API_BASE_URL=…`, **default `http://localhost:3000`**; `requestTimeout` 20 dtk (unggah foto 40 dtk) |

## 2. Struktur kode

```
app/lib/
├── main.dart                 inisialisasi lokal id_ID → ProviderScope → BeOkayApp
├── app.dart                  MaterialApp.router; ukuran teks = skala sistem × preferensi (dijepit 1,0–2,0); reduce-motion
├── core/
│   ├── config/               AppConfig
│   ├── network/              ApiClient, ApiException, AccountScopedRepository, messageFor (pesan galat ramah)
│   ├── storage/              TokenStorage (Secure / Memory)
│   ├── offline/              OfflineQueue, SyncController
│   ├── notifications/        ReminderScheduler (notifikasi lokal)
│   ├── router/               routes.dart, redirect.dart (murni, teruji), app_router.dart
│   ├── theme/                AppColors, AppSpacing, AppTypography, AppTheme
│   ├── widgets/              ±24 komponen bersama (HealthCard, PillButton, DayChart, AsyncBody, …)
│   ├── format/ ids/          pemformat, validator, `newRecordId()` (UUID klien)
│   └── providers.dart        tokenStorage, httpClient, apiClient
└── features/<modul>/
    ├── data/                 model + repository (HTTP)
    ├── application/          controller/provider Riverpod
    └── presentation/         layar & widget
```

Modul fitur (jumlah berkas Dart): `nutrition` 17 (termasuk `scan/`), `insights` 11, `activity` 10, `auth` 8, `glucose` 7, `consent` 6, `medication` 5, `onboarding` 5, `preferences` 5, `profile` 5, `community` 4, `goals` 4, `health_profile` 4, `timeline` 4, `today` 4, `coach` 3, `food_preferences` 3, `home` 3, `interventions` 3, `push` 3, `reminders` 3, `export` 2, `settings` 2, `sync` 2, `quick_record` 1.

## 3. Autentikasi dan perlindungan rute

`AuthController` memiliki empat state: `AuthLoading`, `AuthUnauthenticated(sessionExpired)`, `AuthAuthenticated(user)`, `AuthUnavailable`. Token Bearer dibaca dari header respons `set-auth-token` saat sign-in dan disimpan di Keystore. Bila API membalas `401` pada permintaan bertoken, `ApiClient.onUnauthorized` memicu `sessionExpired()` dan router mengarahkan ke `/login`.

`computeRedirect()` (`core/router/redirect.dart`, fungsi murni dengan tes unit) adalah satu-satunya aturan akses:
1. Loading/Unavailable → `/splash`.
2. Belum masuk → hanya rute publik (`/welcome /register /login /verify-email /forgot-password`); selain itu ke `/welcome` (atau `/login` bila sesi habis).
3. Sudah masuk tetapi onboarding belum siap → `/splash`.
4. Onboarding belum selesai → dipaksa ke langkah yang sesuai `OnboardingState` dan **tidak boleh melompat ke depan** (hanya ke langkah yang sama atau sebelumnya).
5. Onboarding selesai → rute publik/onboarding/splash dialihkan ke `/home`.

## 4. Navigasi

Shell dengan empat tab — **Beranda** (`/home`), **Catatan** (`/log`), **Wawasan** (`/insights`), **Profil** (`/profile`) — ditambah tombol tengah **Catat** yang membuka lembar pencatatan cepat (`quick_record_sheet.dart`), bukan tujuan. Rute lain berada di luar shell: `/meals`, `/glucose`, `/activities` (+ `/new`, `/:id`, `/:id/edit`, `/weekly`), `/medications` (+ edit/riwayat), `/goals`, `/trends`, `/sync`, `/reminders`, `/profile/food-preferences`, `/coach`, `/community` (+ `/community/:id`, `/challenge/:id`), `/settings` (+ `/consent`, `/security`). Rute `/challenge/:id` memerlukan objek `extra` (`Challenge`); bila `null`, dialihkan ke `/community` (penjaga untuk akar masalah yang belum dijelaskan menurut catatan P2).

## 5. Jaringan, akun, dan antrean offline

- **`ApiClient`** — menyisipkan `Authorization: Bearer`, memetakan galat ke `ApiException` (kode `networkCode` untuk timeout/`ClientException`), mem-parse amplop galat server `{error:{code,message,details}}`.
- **`AccountScopedRepository.write()`** — mengambil token **sekali** lalu membuat klien dengan token tertangkap; jika akun berganti di tengah permintaan (`isCurrentAccount()` false) → `ACCOUNT_CHANGED`. Bila jaringan gagal dan penulisan boleh diantrekan (`QueueSpec`: POST pembuatan atau PATCH koreksi), operasi disimpan lalu `QueuedOffline(operationId)` dilempar agar UI menampilkan "tersimpan di perangkat".
- **`OfflineQueue`** — per akun (`beokay.queue.<accountId>`), terenkripsi; koreksi tertunda pada rekaman yang sama digabung; pembuatan tertunda per rekaman hanya satu.
- **`SyncController`** — memuat antrean saat login, mengirim tiap **30 dtk** dan saat aplikasi kembali aktif, dalam kelompok ≤ 50 ke `POST /api/me/sync/operations`; memetakan status server (`SYNCED` dihapus; `CONFLICT`/`NEEDS_REVIEW` menunggu keputusan di layar Sinkronisasi; lainnya `syncFailed` dicoba lagi). Penarikan consent kesehatan → `clearForConsentWithdrawal()` menghapus antrean lokal. Hanya lima domain yang bisa diantrekan (meal, glucose, activity, medication_intake, goal_checkin); fitur lain gagal terang-terangan saat offline.

## 6. Fitur penting dan perilakunya

| Fitur | Perilaku |
|---|---|
| Onboarding | intro → consent (wajib dulu) → profil → kesehatan → preferensi → selesai |
| Consent | kartu per tujuan; teks dampak penarikan dari server; "Menarik persetujuan tidak menghapus data yang sudah tersimpan." |
| Catatan harian | form makan/glukosa/aktivitas/obat/tujuan dengan `newRecordId()`; koreksi memakai `expectedVersion` + alasan (`record_reason_dialog`) |
| Pemindaian | hub → barcode (`mobile_scanner`) / label (OCR) / foto; dialog persetujuan unggah foto; hasil harus diperiksa pengguna (`scan_widgets.dart`) |
| Asisten (`coach`) | permintaan teks → kartu saran → Terima/Tolak → rencana; pulih setelah restart lewat `/agent/pending` |
| Komunitas | direktori provinsi → gabung dengan alias → tantangan → check-in → skor/papan peringkat (ditekan bila kohort kecil) |
| Pengingat | server menyimpan aturan; klien menjadwalkan ≤ 60 notifikasi lokal dengan teks layar kunci generik; mode alarm *inexact* |
| Push | `PushController` mendaftarkan token FCM bila `google-services.json` ada; bila tidak, aplikasi tetap berjalan dan melaporkan push "tidak tersedia" |
| Health Connect | membaca **hanya** sesi olahraga, jarak, langkah (`READ_EXERCISE/DISTANCE/STEPS`); jenis tak dikenal → `other`; dikirim ke `/activities/import` |
| Ekspor | mengunduh JSON, menulis berkas sementara, membagikan lewat share sheet, lalu menghapus berkas |
| Aksesibilitas | skala teks pengguna × sistem (maks 2,0), *reduce motion*, warna domain selalu disertai ikon dan label; kontras brand 9,9:1 menurut komentar tema |

## 7. Tema dan desain

Warna dasar: `brand #0B4F5E` (teal), `emerald #0BA66B`, kanvas `#F1F8F6`. Satu hue per domain kesehatan, tidak pernah dipakai sendirian sebagai pembawa makna. Berkas desain FigCraft tidak ada di repo (folder `design/` dihapus pada commit `833bba5`). **Layar P1 dan sebagian P2/P3 dibangun tanpa desain FigCraft** karena MCP `figcraft` gagal tersambung; mereka memakai ulang komponen dan token yang ada (tercatat di `docs/audits/p1-readiness-audit.md`). Pada sesi audit ini `figcraft` juga gagal tersambung (`CONNECTION_CLOSED`).

## 8. Android

| Hal | Nilai |
|---|---|
| `applicationId` | **`com.example.app`** (placeholder, ada `TODO` di `build.gradle.kts`) |
| `minSdk` | `max(flutter.minSdkVersion, 26)` (Health Connect) · `compileSdk` `max(flutter, 37)` |
| Penandatanganan rilis | memakai kunci **debug** (`signingConfigs.getByName("debug")`) |
| Izin (manifes utama) | `CAMERA`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `health.READ_EXERCISE/DISTANCE/STEPS` |
| `INTERNET` | **tidak ada di manifes utama**; hanya di manifes `debug` dan `profile`. Manifes gabungan rilis **belum diverifikasi** (hanya build debug yang ada) — lihat audit F-03 |
| Firebase | plugin `google-services` diterapkan hanya bila `android/app/google-services.json` ada; berkas itu **tidak ada** di repo |
| Ikon | dihasilkan `flutter_launcher_icons` dari `assets/icon/*` (bukan bagian bundel aset) |

## 9. Pengujian

`app/test/`: `flows/` (24 berkas: alur lintas layar dengan `fake_backend.dart` dan `fake_scheduler.dart`), `unit/` (`redirect_test`, `greeting_test`), `support/`. Tes widget memakai backend palsu, **bukan** server sungguhan; verifikasi ke server nyata dan perangkat dilakukan manual lewat emulator/Appium (hasil di `docs/testing/`). Tes integrasi `integration_test/` tidak ada.

## 10. Menjalankan (di host — Flutter dikecualikan dari aturan Docker)

```bash
cd app && flutter pub get
flutter analyze && flutter test
# perangkat fisik terhubung ke API dev lewat adb:
adb reverse tcp:3000 tcp:3000
flutter run -d <serial> --debug --dart-define=API_BASE_URL=http://localhost:3000
```
