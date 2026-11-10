# Notifikasi push (FCM) — rancangan dan status (9 Nov 2026)

## Keputusan
- Pemilik produk meminta memakai **proyek Firebase/FCM yang sama dengan ceria** untuk notifikasi di produksi. `FCM_PROJECT_ID` dan akun layanan diambil dari `ceria_fooundation` ke `.env` beOkay (gitignored, mode 600). Nilai rahasia tidak ada di berkas ter-track.
- Server mengirim lewat **FCM HTTP v1** dengan klien buatan sendiri (`server/src/features/push/fcm.client.ts`, tanpa dependensi baru): JWT RS256 dari kunci akun layanan → token akses OAuth (di-cache) → `messages:send`. Host OAuth dan FCM dipaku, tanpa redirect.
- Push **opsional per perangkat** (saklar di layar Pengingat, hanya tampil bila Firebase terkonfigurasi). Pengingat tetap bisa berjalan hanya sebagai **notifikasi lokal**. Bila push aktif di sebuah perangkat, perangkat itu **mengosongkan jadwal lokalnya** agar tidak ada notifikasi ganda.

## Alur
1. Klien: izin notifikasi → token FCM → `POST /api/me/push-devices` (butuh consent kesehatan; token tidak pernah dikembalikan utuh, hanya `tokenHint`).
2. Server: `push-dispatcher` berjalan tiap 30 dtk. Untuk tiap akun dengan perangkat aktif dan consent kesehatan, menghitung pengingat yang jatuh tempo dalam 3 menit terakhir (DST-aman, zona waktu pengguna) dan mengirim ke semua perangkat aktif.
3. Idempotensi: `push_deliveries` unik per (pengingat, perangkat, waktu jadwal). Putaran ganda atau beberapa instans tidak mengirim dua kali.
4. Token tidak berlaku (`UNREGISTERED`, `NOT_FOUND`, `SENDER_ID_MISMATCH`) → perangkat dinonaktifkan. Gagal sementara dicatat `failed` tanpa menonaktifkan.
5. Logout: klien mencabut perangkat (hapus di server + hapus token FCM). Consent ditarik: dispatcher melewati akun itu dan klien membatalkan notifikasi lokal. Hapus akun: perangkat dan buku besar terhapus (cascade).

## Privasi
Isi pesan **selalu generik** ("Pengingat beOkay" / "Buka beOkay untuk mencatat."), tanpa judul buatan pengguna, nama obat, atau angka; `visibility=PRIVATE`; `data` hanya `{type:"reminder"}`. Tidak ada tujuan consent baru: pendaftaran perangkat adalah tindakan eksplisit pengguna dan butuh consent `health_data_processing`. **Perlu ditinjau pemilik produk/hukum** apakah token perangkat memerlukan tujuan consent tersendiri (menaikkan versi kebijakan memaksa persetujuan ulang semua pengguna, jadi tidak dilakukan diam-diam).

## Konfigurasi
| Variabel | Keterangan |
|---|---|
| `FCM_PROJECT_ID` | ID proyek Firebase |
| `FCM_SERVICE_ACCOUNT_JSON` | JSON akun layanan dalam **base64** (`base64 -w0 berkas.json`); JSON mentah multi-baris merusak shell/compose |
| `PUSH_DISPATCH_ENABLED` | `true` di produksi. Di dev compose bawaannya `false` (lewat `PUSH_DISPATCH_ENABLED_DEV`) agar data uji tidak mengirim push sungguhan |

Produksi: isi ketiganya sebagai env/secret pada `compose.prod.yaml` (sudah diteruskan). Tanpa `FCM_*`, push nonaktif tanpa galat.

## Yang sudah terverifikasi
- Kredensial: pengiriman `validate_only` ke proyek FCM sungguhan dengan token dummy menghasilkan OAuth berhasil dan FCM `400 INVALID_ARGUMENT` (bukan 401/403), jadi akun layanan dan proyek sah. Tidak ada pesan yang terkirim ke perangkat mana pun.
- Server: 8 tes unit klien FCM (tanda tangan JWT diverifikasi dengan kunci uji yang dibangkitkan saat tes, cache token, klasifikasi galat, penolakan `token_uri` asing) dan 5 tes integrasi (pendaftaran, isolasi, batas 5 perangkat, dispatcher idempoten, consent, token tidak berlaku, cascade).
- Klien Flutter: tes dengan klien Firebase palsu (tidak tersedia, izin ditolak, daftar/cabut, token diperbarui, jadwal lokal dikosongkan saat push aktif).

- Emulator (API 37, build dengan `firebase_core`/`firebase_messaging` tanpa `google-services.json`): aplikasi tidak crash; log Firebase hanya menyatakan inisialisasi gagal karena tidak ada opsi bawaan (diharapkan); layar Pengingat normal dan saklar push tersembunyi. `flutter build apk --debug` berhasil (peringatan: `firebase_core` dan `health` masih memakai Kotlin Gradle Plugin lama).

## Yang BELUM ada / belum terverifikasi
1. **Aplikasi beOkay belum terdaftar di proyek Firebase itu.** Proyek `ceria` hanya memuat aplikasi Android `com.example.ceria` dan `com.example.ceria_app`; beOkay memakai `com.example.app` (nama bawaan Flutter, perlu diganti ke ID yang sebenarnya sebelum rilis). Tanpa `android/app/google-services.json` untuk ID beOkay, perangkat tidak mendapat token, saklar push tersembunyi, dan pengingat memakai notifikasi lokal. **Langkah yang harus dilakukan pemilik:** daftarkan aplikasi Android beOkay (dan iOS bila ada) di konsol Firebase proyek tersebut, unduh `google-services.json`, taruh di `app/android/app/`. Plugin Gradle google-services hanya diterapkan bila berkasnya ada. Jangan memakai `google-services.json` ceria untuk beOkay: itu membuat dua produk berbagi ID aplikasi.
2. **Pengiriman push ke perangkat nyata belum diuji** (tidak ada token nyata). Hanya `validate_only` dan tes dengan pengirim palsu.
3. **iOS di luar cakupan** (keputusan pemilik: Android saja). Tidak ada konfigurasi APNs/`GoogleService-Info.plist`.
4. **Tidak ada antrean coba-ulang**: pengiriman yang `failed` pada jendela 3 menit tidak diulang. Pengingat basi dianggap lebih buruk daripada hilang.
5. Satu proses pengirim berjalan di tiap instans API; aman untuk beberapa instans karena buku besar, tetapi semua instans akan mencoba (hanya satu yang menang per pengiriman).
6. Sesi yang kedaluwarsa tidak mencabut perangkat (tidak ada kredensial untuk memanggil server); perangkat tetap menerima pengingat generik akun itu sampai masuk ulang atau token dipindah akun lain.
7. **Risiko berbagi akun layanan:** satu kredensial untuk dua produk memperluas dampak kebocoran. Disarankan akun layanan terpisah dengan peran minimum (hanya FCM) untuk beOkay produksi.
8. `firebase_messaging` 17 menandai `getToken` usang demi FID; dipertahankan API token standar karena kecocokan FID dengan HTTP v1 belum terbukti.
