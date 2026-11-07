# Pengujian Authentication & Personalization

## 8 November 2026 — emulator dan stack uji

APK debug dijalankan pada emulator Android Pixel_4 melalui Appium UiAutomator2. API, PostgreSQL dan Mailpit menggunakan `compose.test.yaml`; akun dan data yang digunakan adalah sintetis. Email verifikasi diambil dari Mailpit uji dan tautannya dipanggil pada jaringan Docker.

Alur yang teramati melalui Appium dan API nyata: registrasi, verifikasi email, login, intro, consent wajib tanpa memilih consent opsional, profil pribadi, status kesehatan tidak diketahui, pilihan mmol/L, penyelesaian onboarding, dan kembali ke beranda. Aplikasi dihentikan dan dibuka kembali; sesi dan mmol/L dipulihkan. Perubahan tahun lahir ke 1990 tersimpan dan dikonfirmasi di PostgreSQL. Consent pemrosesan kesehatan ditarik, diberikan ulang, kemudian ditarik kembali. Akun tetap dapat dibuka dan layar kesehatan menampilkan `Persetujuan diperlukan`.

Logout melalui pengaturan dan dialog konfirmasi mengembalikan aplikasi ke welcome. Setelah selesai, emulator dan API uji dibiarkan berjalan; akun sintetis berada di database uji sementara.

Temuan privasi: sebelum perbaikan, profil kesehatan yang sudah dimuat tetap terlihat dari cache setelah penarikan consent. Setelah invalidasi provider dan pencegahan tampilan nilai lama saat loading/error, tes regresi dan pemeriksaan Appium ulang menampilkan batasan consent. Endpoint server juga diuji menolak akses pada tes integrasi.

Temuan terbuka: setelah menyimpan perubahan profil pribadi pada emulator, aplikasi kembali ke beranda meskipun perubahan tersimpan; perilaku kembali ke halaman profil perlu diperiksa. Pengujian Appium ini belum mencakup pemulihan password, dua akun dan isolasi kepemilikan, seluruh pengaturan, atau pemeriksaan aksesibilitas dan visual yang menyeluruh.

Verifikasi otomatis setelah perubahan: `flutter test` 24 lulus; `docker compose -f compose.test.yaml run --rm tester bun test` 1 lulus, 20 assertion. Tes Flutter menggunakan fake backend, sedangkan tes integrasi server menggunakan database dan Mailpit terisolasi. Jangan menganggap hasil ini sebagai bukti semua skenario E2E atau audit keamanan lengkap.
