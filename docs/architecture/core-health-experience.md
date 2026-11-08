# Core Health Experience

Pembaruan Slice 3: [arsitektur Glucose](glucose.md) memperluas tracking online, Today dan preview sumber, timeline read model meal+glucose serta daily composite. Quick Record food/glucose aktif. Fondasi auth/onboarding tetap dipakai. Bagian Slice 1–2 di bawah adalah histori, bukan status fitur terbaru.

Pembaruan Slice 2: [arsitektur Nutrition](nutrition.md) sudah diterapkan. Today mengonsumsi read model Nutrition nyata, Quick Record food aktif, dan rute meal tersedia. Bagian Slice 1 di bawah dipertahankan sebagai catatan fondasi; daftar fitur belum tersedia harus dibaca bersama laporan Nutrition terbaru.

## Slice 1 — Today Foundation

`GET /api/me/today` melewati `authenticated` (sesi Better Auth terverifikasi), kemudian `todayService` memeriksa consent current `health_data_processing` dan `descriptive_summaries`. Respons memakai kembali `profileService` dan `preferencesService`, selalu dengan identitas sesi. Identitas dari klien tidak digunakan.

Dependensi: `today → auth / consent / profile / preferences`; tidak ada modul existing yang bergantung pada Today. Tidak perlu repository tambahan: Today mengorkestrasi repository milik fitur existing melalui service masing-masing. Tidak ada cache server atau tabel universal baru.

## Kontrak dan waktu

Tanggal `YYYY-MM-DD` dan greeting dihitung dengan IANA timezone tersimpan melalui `Intl.DateTimeFormat.formatToParts`. Jam 05–10 pagi, 11–14 siang, 15–17 sore, selainnya malam. `generatedAt` adalah waktu respons, bukan waktu komputasi summary kesehatan. `computationVersion=today-foundation-v1`; `analyticsState=NOT_AVAILABLE`. Tidak ada klaim analytics READY atau histori kosong yang sudah ditelusuri.

`metrics[]` memuat domain dan availability `NOT_IMPLEMENTED`, value `null`. `goals`/`timeline` juga memiliki availability; items kosong hanya berarti feature belum tersedia. Nilai null tidak diganti nol. Provider Flutter saat ini membaca metadata tanggal, greeting, timezone, unit; kartu adalah preview foundation, belum renderer metrik domain. Saat domain pertama ditambahkan, perlu perluas model Flutter dan kontrak kartu untuk membedakan `AVAILABLE`/empty/partial secara eksplisit.

## Flutter dan lifecycle

`features/today/{data,application,presentation}` memakai ApiClient, secure bearer storage, Riverpod dan tema existing. Home tetap memakai greeting nama auth dan warning profil/consent existing, kemudian TodaySection. Profil dapat dibuka lewat avatar. FutureProvider autoDispose bergantung pada auth, consent, preferensi dan profil. Refresh/reload/error tidak menampilkan AsyncValue lama. Timer satu menit dan app resume memuat ulang tanggal/metadata; tombol muat ulang tersedia. Akses tanpa sesi tidak membuat request Today.

Pengujian provider pending-response saat pergantian akun belum terpisah; isolasi API dua akun sudah diuji. Tidak ada penyimpanan health lokal atau offline cache pada slice ini. Kegagalan koneksi menampilkan error dan retry. Foundation bukan klaim implementasi FEAT-10.

## Pengembangan berikutnya

Nutrition menambahkan domain record, form, revision dan query Today yang terbatas hari pengguna. Timeline/insight nantinya berasal dari record domain, tanpa duplikasi writable universal. Unit dan snapshot harus dipertahankan. Four-tab navigation dan Quick Record baru ditambahkan ketika destination tersedia. Setelah Nutrition, berhenti kembali untuk review kode.
