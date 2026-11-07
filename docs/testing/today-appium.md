# Today Foundation — verifikasi Appium

8 November 2026 WIB; selesai mencatat hasil pada 7 November 2026 23:43:59 UTC. Cakupan hanya Slice 1 Today Foundation beserta integrasi fondasi existing. Tidak ada implementasi fitur berikutnya atau perubahan source aplikasi pada pengujian ini.

## Lingkungan

- Android emulator AVD Pixel_4, `emulator-5554`, Android 17 / API 37, resolusi 1080×2280, system font scale 1.0.
- Appium MCP embedded, driver UiAutomator2. APK debug `app/build/app/outputs/flutter-apk/app-debug.apk` dipasang dengan install ulang yang mempertahankan data.
- Backend nyata Bun/Prisma, PostgreSQL dan Mailpit dari `compose.test.yaml`; tanpa database dev. Override sementara `/tmp/beokay-appium-compose.yaml` memublikasikan API uji hanya pada `127.0.0.1:3300`.
- `adb reverse tcp:3000 tcp:3300` menghubungkan default API APK `localhost:3000` ke API uji. Tidak mengubah konfigurasi aplikasi produksi/dev.
- Dua akun sintetis, password random runtime. Registrasi, email verification Mailpit, consent, profil, health profile unknown, preferensi dan onboarding dipersiapkan lewat API. Login aplikasi, perubahan unit, consent dan logout dijalankan melalui UI Appium.

## Hasil observasi

**13 skenario terverifikasi, tidak ditemukan kegagalan produk pada skenario ini.** Ini adalah eksekusi interaktif melalui MCP, bukan hasil runner suite Appium mandiri. [Catatan terstruktur](artifacts/today-appium/results.json).

| No. | Skenario | Hasil |
|---|---|---|
| 1 | Login akun A dan konteks Today | PASS: nama A, Pacific/Honolulu, Selamat siang, mmol/L; tanggal 7 November sesuai API |
| 2 | Scroll ringkasan hingga goals/insight dan akses refresh | PASS: preview Glukosa/Nutrisi/Aktivitas/Obat jujur belum tersedia, konten bawah dapat dijangkau |
| 3 | Force-stop lalu buka ulang aplikasi | PASS: sesi A dipulihkan ke Today |
| 4 | Avatar Today ke Profil | PASS: profil dan preferensi akun A tampil |
| 5 | Ganti unit lewat Pengaturan | PASS: pilih mg/dL, kembali ke Today; preferensi baru tampil |
| 6 | Putus koneksi API lalu refresh | PASS: error koneksi, Coba lagi, konten Today lama tidak tampil |
| 7 | Pulihkan koneksi lalu Coba lagi | PASS: Today dan unit mg/dL tampil kembali |
| 8 | Tarik health_data_processing melalui UI dan konfirmasi | PASS: Today dibatasi, Persetujuan diperlukan, tidak ada kartu Glukosa lama |
| 9 | Beri consent lagi melalui UI | PASS: Today tersedia kembali |
| 10 | Logout dengan dialog konfirmasi | PASS: kembali ke welcome |
| 11 | Login akun B setelah A | PASS: nama B, Asia/Jakarta, Selamat pagi, 8 November, mg/dL; nama dan zona waktu A tidak terlihat |
| 12 | Refresh manual akun B | PASS: respons Today selesai dimuat dari API nyata |
| 13 | Cabut sesi B di Better Auth, background/resume aplikasi | PASS: menuju login, pesan Sesimu sudah berakhir, tidak ada konten Today B |

Tanggal A dan B sengaja berbeda karena pada waktu pengujian Honolulu masih 7 November sedangkan Jakarta sudah 8 November. Perbandingan memakai respons API nyata, bukan tanggal contoh statis. Pencabutan sesi memakai endpoint Better Auth untuk seluruh sesi akun sintetis B; respons 200 sebelum app resume.

Gangguan koneksi disimulasikan dengan menghapus ADB reverse lalu memasangnya kembali. Ini membuktikan penanganan API tidak terjangkau; bukan pengujian radio jaringan Android, offline record persistence atau sync queue. Setelah gangguan tersebut, layar consent sempat menampilkan error tersimpan; tombol Coba lagi berhasil memuatnya kembali.

Beberapa pencarian locator awal tidak cocok karena transisi masih berlangsung atau label aktual berbeda: dialog Google Password Manager menutupi home, unit di Profil membuka Pengaturan dahulu, status consent memakai Ditarik, dan sesi dicabut mengarah ke login. Locator/alur disesuaikan berdasarkan page source dan hasil akhir diverifikasi. Password Manager ditutup dengan Not now; tidak menyimpan akun ke Google.

## Bukti visual

Screenshot berikut diambil langsung dari Appium dan sudah dibuka untuk inspeksi. Teks, unit, status error/consent dan navigasi terbaca; tidak tampak overflow pada area yang diperiksa. Konten bawah diperiksa melalui scroll. Ini belum audit aksesibilitas atau visual lintas perangkat secara menyeluruh.

- [Today A / Honolulu](artifacts/today-appium/todayA.png)
- [Bagian bawah dashboard](artifacts/today-appium/bottom.png)
- [Error koneksi](artifacts/today-appium/networkError.png)
- [Consent ditarik](artifacts/today-appium/consentBlocked.png)
- [Today B / Jakarta](artifacts/today-appium/todayB.png)
- [Sesi dicabut](artifacts/today-appium/revokedSession.png)

## Batas dan replay

Belum mencakup iOS, perangkat fisik, font scale besar di emulator, screen reader, pergantian akun saat request masih tertunda, midnight saat aplikasi terus aktif, cold start tanpa jaringan, maupun operasi health record yang memang belum diimplementasikan. Tes 320 px/text scale 2 sebelumnya merupakan tes widget Flutter terpisah.

Untuk replay: nyalakan stack uji dan emulator, pasang APK debug, konfigurasi ADB reverse, buat dua fixture sintetis terverifikasi dengan timezone/unit berbeda, lalu ikuti tabel skenario melalui Appium. Gunakan accessibility id untuk label Flutter; field login dikenali lewat class EditText. Jangan menyimpan kredensial dalam collection, source, screenshot atau laporan. Skrip fixture hanya berada di `/tmp`, bukan repository. Sesi Appium, emulator headless dan stack uji dibersihkan setelah pengujian; data dev tidak diubah.
