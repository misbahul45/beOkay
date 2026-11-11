# Aplikasi Mobile (Flutter)

> Diaudit 10 November 2026. Lokasi: `app/`. Target: **Android saja** (keputusan pemilik; tidak ada iOS/HealthKit). Folder `ios/`, `macos/`, `linux/`, `windows/`, `web/` ada karena `flutter create`, tetapi tidak dipakai.
> Status: `flutter analyze` → *No issues found*; `flutter test` → **175 tes lulus** (setelah beOkay 3.0 Fase 2).

## 1. Ringkasan teknis

| Hal | Nilai |
|---|---|
| SDK | Dart `^3.12.2`, versi aplikasi `1.0.0+1` |
| State | `flutter_riverpod ^3.5` (`Notifier`/`Provider`; `ProviderScope(retry: (_, _) => null)` — tanpa auto-retry provider) |
| Navigasi | `go_router ^18` dengan `redirect` terpusat |
| HTTP | paket `http` lewat `ApiClient` sendiri (tanpa Dio) |
| Penyimpanan | `flutter_secure_storage` (token sesi, antrean offline, status push) — Keystore Android |
| Tampilan | tema terang dan gelap mengikuti sistem (`AppPalette.light/dark`, token diambil lewat getter `AppColors`; router dibuat ulang saat tema berganti), font Inter (400/600/700), bahasa tunggal `id_ID` |
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
│   ├── widgets/              ±26 komponen bersama (HealthCard, PillButton, DayChart, AsyncBody, form_kit, detail_kit, …)
│   ├── format/ ids/          pemformat, validator, `newRecordId()` (UUID klien)
│   └── providers.dart        tokenStorage, httpClient, apiClient
└── features/<modul>/
    ├── data/                 model + repository (HTTP)
    ├── application/          controller/provider Riverpod
    └── presentation/         layar & widget
```

Modul fitur (jumlah berkas Dart): `nutrition` 17 (termasuk `scan/`), `insights` 14, `activity` 10, `auth` 8, `glucose` 7, `consent` 6, `medication` 5, `onboarding` 5, `preferences` 5, `profile` 5, `community` 7, `notifications` 5, `goals` 4, `health_profile` 4, `timeline` 4, `today` 4, `coach` 7, `food_preferences` 3, `home` 3, `interventions` 3, `push` 3, `reminders` 3, `export` 2, `settings` 2, `sync` 2, `quick_record` 1.

## 3. Autentikasi dan perlindungan rute

`AuthController` memiliki empat state: `AuthLoading`, `AuthUnauthenticated(sessionExpired)`, `AuthAuthenticated(user)`, `AuthUnavailable`. Token Bearer dibaca dari header respons `set-auth-token` saat sign-in dan disimpan di Keystore. Bila API membalas `401` pada permintaan bertoken, `ApiClient.onUnauthorized` memicu `sessionExpired()` dan router mengarahkan ke `/login`.

`computeRedirect()` (`core/router/redirect.dart`, fungsi murni dengan tes unit) adalah satu-satunya aturan akses:
1. Loading/Unavailable → `/splash`.
2. Belum masuk → hanya rute publik (`/welcome /register /login /verify-email /forgot-password`); selain itu ke `/welcome` (atau `/login` bila sesi habis).
3. Sudah masuk tetapi onboarding belum siap → `/splash`.
4. Onboarding belum selesai → dipaksa ke langkah yang sesuai `OnboardingState` dan **tidak boleh melompat ke depan** (hanya ke langkah yang sama atau sebelumnya).
5. Onboarding selesai → rute publik/onboarding/splash dialihkan ke `/home`.

## 4. Navigasi

Sejak beOkay 3.0 Fase 1: shell dengan empat tujuan, yaitu **Beranda** (`/home`), **Catatan** (`/log`), **Asisten** (`/coach`), dan **Wawasan** (`/insights`), ditambah tombol tengah **Catat** di dalam bar yang membuka lembar pencatatan cepat (`quick_record_sheet.dart`), bukan tujuan. **Profil** (`/profile`) tetap di dalam shell tetapi dibuka lewat avatar (`ProfileAction`) di kanan atas setiap akar tab; saat di Profil tidak ada tab yang tersorot. Header Beranda menampilkan logo (`BeOkayLogo`, varian `logo_full_dark.png` di mode gelap). Profil berisi kartu identitas, kartu konteks diabetes, ubin rutinitas (Tujuan, Obat, Pengingat, Komunitas; satu kolom pada teks besar), kelompok Asisten & personalisasi, Data & keamanan, dan Aplikasi; preferensi tidak diulang di Profil, hanya diringkas pada baris Pengaturan aplikasi. Path `/coach` tidak berubah, jadi tautan lama tetap bekerja. Label bar mengecil (`FittedBox`) alih-alih terpotong pada teks besar. Rute lain berada di luar shell: `/meals`, `/glucose`, `/activities` (+ `/new`, `/:id`, `/:id/edit`, `/weekly`), `/medications` (+ edit/riwayat), `/goals`, `/trends`, `/sync`, `/reminders`, `/profile/food-preferences`, `/community` (+ `/community/:id`, `/challenge/:id`), `/settings` (+ `/consent`, `/security`). Sejak Fase 6 juga `/community/privacy`, `/notifications`, dan `/settings/notifications`; `/challenge/:id` membaca tantangan dari server berdasarkan ID (tidak lagi butuh `extra`), sehingga notifikasi dan percakapan bisa membukanya langsung. Tombol Kembali sistem pada Catatan, Asisten, Wawasan, dan Profil kembali ke Beranda (`BackToHome`, `PopScope` di halaman tab di dalam navigator shell); hanya di Beranda tombol itu menutup aplikasi. Lonceng notifikasi (`NotificationBell`, lencana belum dibaca, "9+") ada di header setiap akar tab.

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
| Asisten (`coach`) | sejak 3.0 Fase 3: percakapan (`/api/me/conversations`). `ConversationController` memegang thread aktif, pesan tertunda (kirim ulang memakai `clientMessageId` yang sama), dan saran yang sedang diputuskan (`operationId` dipakai ulang saat mengulang). Bagian balasan dirender per tipe di `chat_parts.dart`: gelembung teks, kartu statistik, kartu hasil ringkas (satu utama, sisanya di balik "Lihat N pilihan lain") + lembar detail, kartu tidak ketemu, kartu keselamatan, consent, chip saran (hanya pada balasan terakhir) dan tautan. Riwayat thread dan rencana makan/aktivitas ada di lembar "Riwayat & rencana". Thread terakhir (< 24 jam) dipulihkan saat aplikasi dibuka |
| Wawasan (`insights`) | sejak redesign UI/UX: tiga bagian **Ringkasan · Tren · Harian** (`insightsSectionProvider`). Ringkasan memakai `insight_presentation.dart` (prioritas insight deterministik, satu aksi per kartu, kartu metrik ringkas, perbandingan hanya bila datanya cukup) dan lembar detail bertingkat (konteks → "Tentang data"). Versi analisis tidak pernah tampil. Tren memakai `TrendsBody` (juga di `/trends`). Harian: navigator tanggal + ringkasan empat domain, termasuk obat untuk tanggal terpilih. Lihat [redesign](../reports/beokay-3.0-uiux-redesign.md) |
| Asisten — Fase 4 | draf catatan makan dari kalimat atau foto (`MealDraftCard`, penyunting draf: kategori, waktu, pilihan makanan, jumlah, berat opsional); tombol "Cari di web" per makanan yang tidak ada di referensi (dialog persetujuan pengiriman, hasil berlabel "Web · belum diverifikasi"); kartu usulan ingatan (Ingat/Jangan); tautan "Dasar jawaban". Tombol kamera di penyusun memakai alur foto yang sudah ada (dialog unggah) lalu mengirim nama hasilnya, bukan gambar |
| Memori & personalisasi (`/settings/memory`) | sakelar ingatan, daftar ingatan (ubah/hapus/hapus semua), tautan preferensi makanan, ringkasan saran yang ditolak dengan atur ulang |
| Rencana kecil (`/coaching`) | sejak 3.0 Fase 5: kartu refleksi mingguan, usulan dengan "Kenapa ini?" (bukti dan ingatan yang dipakai), lembar mulai rencana (waktu dan pengingat opsional), kartu rencana dengan chip per hari (tercatat, dikonfirmasi, belum terlihat; ketuk hari yang lewat untuk mengonfirmasi), lembar umpan balik delapan pilihan + hentikan rencana. Dibuka dari Profil, kartu Beranda, atau percakapan |
| Refleksi mingguan (`/coaching/reflection`) | ringkasan dari catatan → dua pertanyaan (perasaan, bagian tersulit, catatan opsional) → penyesuaian (sakelar per tujuan, default mati; waktu yang enak; "Ingat waktu ini") → pengakuan usaha. `operationId` dibuat sekali per layar sehingga kirim ulang aman |
| Komunitas | sejak 3.0 Fase 6: hub (`/community`) berisi tantanganmu dengan progres, pencapaian pribadi (terkunci/tercapai; satu kolom pada teks besar), komunitasku, dan direktori provinsi. Detail komunitas mengelompokkan tantangan Berjalan · Akan datang · Selesai. Detail tantangan (`/challenge/:id`): status dan sisa hari, progres hari aktif, check-in hari ini (tombol berubah menjadi "Sudah check-in hari ini"), cara kerja, hasil saat selesai, papan peringkat (berlangganan topik `challenge:<id>` sehingga berubah langsung). Lembar gabung meminta alias dan pilihan tampil di papan peringkat (default mati). Privasi komunitas (`/community/privacy`): yang dibagikan vs tidak pernah dibagikan, sakelar sorotan Beranda, sembunyikan dari semua papan peringkat. Kartu sorotan di Beranda setelah "Hari ini" |
| Notifikasi | sejak 3.0 Fase 6: `RealtimeController` membuka WebSocket `/api/me/realtime` (dart:io, header `Authorization`), `ping` tiap 25 dtk, sambung ulang dengan jeda bertahap, berlangganan ulang topik setelah tersambung; event `notification` menaikkan lencana dan menampilkan banner di dalam aplikasi (ketuk = buka tujuan `routeForAction`). Kotak masuk (`/notifications`) dikelompokkan per hari, status sambungan langsung, tandai dibaca satu/semua, muat lebih banyak. Pengaturan (`/settings/notifications`): sakelar push dan per jenis. Notifikasi push yang diketuk (FCM, saat aplikasi berjalan atau dari keadaan mati) membuka tujuan yang sama. Tes memakai `SilentRealtimeConnector` |
| Form & detail | sejak 3.0 Fase 6 semua form pencatatan (glukosa, aktivitas, makan, obat, tujuan, profil, profil kesehatan, pengingat) memakai `form_kit.dart`: `FormHero` per domain, `FormSection` berjudul, `DateTimeTile`, `FormNote`, dan `SaveBar` tetap di bawah dengan catatan offline. Halaman detail (glukosa, makan, aktivitas, riwayat obat) memakai `detail_kit.dart`: `DetailHero` (nilai besar + chip waktu/sumber), `DetailSection` + `DetailRow` (label/nilai, bertumpuk pada teks besar), `DetailActions`, `RevisionTimeline`, dan bagian provenans |
| Pengingat | server menyimpan aturan; klien menjadwalkan ≤ 60 notifikasi lokal dengan teks layar kunci generik; mode alarm *inexact* |
| Push | `PushController` mendaftarkan token FCM bila `google-services.json` ada; bila tidak, aplikasi tetap berjalan dan melaporkan push "tidak tersedia" |
| Health Connect | membaca **hanya** sesi olahraga, jarak, langkah (`READ_EXERCISE/DISTANCE/STEPS`); jenis tak dikenal → `other`; dikirim ke `/activities/import` |
| Ekspor | mengunduh JSON, menulis berkas sementara, membagikan lewat share sheet, lalu menghapus berkas |
| Aksesibilitas | skala teks pengguna × sistem (maks 2,0), *reduce motion*, warna domain selalu disertai ikon dan label; kontras brand 9,9:1 menurut komentar tema |

## 7. Tema dan desain

Sejak beOkay 3.0 Fase 1 (FigCraft halaman 20): brand `#16796F` (teal, putih di atasnya 5,25:1), mint `#DDF4E8`, kanvas `#F8F9F6`, teks sekunder `#5C6B73` (≥ 4,7:1 di atas semua tint). Tiap domain punya `tint`, `solid` (grafik), dan `ink` (teks/ikon, ≥ 4,5:1); warna tidak pernah dipakai sendirian sebagai pembawa makna. Pendamping **beOkay Spark** (`core/widgets/beokay_spark.dart`) punya 10 keadaan, gerak terbatas, dan diam saat *reduce motion*; ia mewakili aktivitas asisten, bukan nilai kesehatan. Mode gelap terpasang sejak 10 Nov 2026 dan mengikuti pengaturan sistem; kontras kedua palet diuji otomatis (`test/unit/palette_contrast_test.dart`). Berkas FigCraft ada di `design/beOkay-ui-v3.figcraft` (ekspor PNG di `design/exports/`). Sebagian layar P1–P3 lama dibangun tanpa desain FigCraft (tercatat di `docs/audits/p1-readiness-audit.md`).

## 8. Android

| Hal | Nilai |
|---|---|
| `applicationId` / namespace | `id.beokay.app` (sejak 10 Nov 2026) |
| `minSdk` | `max(flutter.minSdkVersion, 26)` (Health Connect) · `compileSdk` `max(flutter, 37)` |
| Penandatanganan rilis | dari `android/key.properties` (gitignored); tanpa berkas itu, atau tanpa `API_BASE_URL=https://…`, build rilis gagal dengan pesan jelas |
| Izin (manifes utama) | `CAMERA`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `health.READ_EXERCISE/DISTANCE/STEPS` |
| `INTERNET` | di manifes utama; terverifikasi pada APK rilis (`aapt dump badging`) |
| Firebase | plugin `google-services` diterapkan hanya bila `android/app/google-services.json` ada; berkas itu **tidak ada** di repo |
| Ikon | dihasilkan `flutter_launcher_icons` dari `assets/icon/*` (bukan bagian bundel aset) |

## 9. Pengujian

`app/test/`: `flows/` (28 berkas: alur lintas layar dengan `fake_backend.dart` dan `fake_scheduler.dart`), `unit/` (`redirect_test`, `greeting_test`), `support/`. Tes widget memakai backend palsu, **bukan** server sungguhan; verifikasi ke server nyata dan perangkat dilakukan manual lewat emulator/Appium (hasil di `docs/testing/`). Tes integrasi `integration_test/` tidak ada.

## 10. Menjalankan (di host — Flutter dikecualikan dari aturan Docker)

```bash
cd app && flutter pub get
flutter analyze && flutter test
# perangkat fisik terhubung ke API dev lewat adb:
adb reverse tcp:3000 tcp:3000
flutter run -d <serial> --debug --dart-define=API_BASE_URL=http://localhost:3000
```
