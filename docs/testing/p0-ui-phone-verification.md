# Verifikasi UI P0 (stage 1) — perangkat fisik

8 November 2026 (WIB). Cakupan: navigasi 4 tab, Beranda, Catatan, Wawasan, Quick Record. Bukan verifikasi P0 penuh.

## Lingkungan

- HP Redmi `2409BRN2CY`, Android 15 (API 35), 720×1640, density 320. APK debug dipasang dengan `flutter run -d … --no-resident`.
- Backend: stack dev (`docker compose up -d --build`), API `127.0.0.1:3000` diteruskan ke HP dengan `adb reverse tcp:3000 tcp:3000`. Mailpit di `127.0.0.1:8025`.
- Akun sintetis dibuat lewat API dengan password acak per eksekusi (tidak disimpan di repo). Verifikasi email lewat Mailpit; onboarding diselesaikan lewat API; login dilakukan lewat UI di HP. Dialog Google Password Manager dijawab "Not now".
- Data contoh: 1 sarapan, 2 glukosa (96 dan 142 mg/dL), 1 sesi jalan kaki 30 menit.
- Appium UiAutomator2 dipakai untuk mengisi field; ketukan dan tangkapan layar memakai adb.

## Hasil yang diamati langsung di HP

| Skenario | Hasil |
|---|---|
| Login lewat UI lalu Beranda | PASS: 4 tab, kartu Glukosa/Nutrisi/Aktivitas berisi data nyata, "Catatan terbaru" berurutan menurut waktu kejadian |
| Tab Catatan | PASS: kelompok per tanggal, chip filter, tile menampilkan sumber ("glukometer manual", "dilaporkan sendiri") dan konteks ("Setelah makan") |
| Chip "Diarsipkan" | PASS: empty state "Belum ada catatan diarsipkan" |
| Ketuk tile glukosa → detail | PASS: membuka "Detail glukosa" untuk record asli (142 mg/dL, 20:45) |
| Quick Record dari Beranda → Glukosa | PASS: sheet menampilkan 3 opsi aktif + "Konsumsi obat" nonaktif jelas, ketuk Glukosa membuka form "Catat glukosa" (pengisian dan penyimpanan tidak diuji di HP) |
| Tab Wawasan | PASS: navigasi hari, statistik hanya bila server menyatakan READY, "Langkah/Jarak: Belum diketahui" (bukan 0), catatan cara membaca |
| Font scale 2.0 (sebelum perbaikan) | **GAGAL** pada 3 titik: judul Catatan patah, label nav terpotong, badge memecah judul |
| Font scale 2.0 (setelah perbaikan) | PASS pada Beranda, Catatan, Wawasan (judul utuh, label nav terbaca, badge di baris sendiri). Hanya bagian atas tiap layar yang diperiksa |

Font scale HP dikembalikan ke nilai awal (1.0).

## Tes otomatis

- `flutter analyze`: no issues.
- `flutter test`: 59 lulus (sebelumnya 52). Ditambah `test/flows/log_insights_test.dart` (filter = query API dan baris yang tampil, tile membuka record asli, empty state pada 320px/teks 2×, unknown tidak menjadi 0, statistik jarang diberi label, tanpa overflow pada 360px/teks 2×). Tes Beranda dan alur identitas diperbarui ke teks desain baru; maksud asersinya (navigasi ke record asli, empty state jujur, 320px/teks 2×) dipertahankan.
- Batas tes widget: font tes monospasi-persegi, sehingga pemecahan baris tidak bisa diasersikan; itu dibuktikan di HP, bukan di tes.

## Belum diuji

Penyimpanan record dari form di HP, dark mode, orientasi landscape, TalkBack, perangkat lain, backend tes otomatis (tidak ada perubahan server pada stage ini), Bruno, pengguna kedua / pergantian akun di perangkat, keadaan offline, paginasi "Muat catatan lebih lama" (data contoh < 20 baris; hanya diuji lewat kode).
