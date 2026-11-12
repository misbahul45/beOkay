# beOkay 3.0 — Fase 11: Ekosistem

> Tanggal: 12 November 2026. Cakupan dari [gap analysis §8](../audits/gap-analysis-2026-11-12.md): K-4, K-7, K-8, K-3, K-11, D-6, U-2, U-4.
> Desain FigCraft: halaman "32 — Fase 11: Ekosistem" di `design/beOkay-ui-v3.figcraft`, ekspor `design/exports/32-*.png` (16 frame), dibuat **sebelum** UI fase ini ditulis. Server MCP `figcraft` tidak tersambung di sesi ini; halaman dibuat lewat `figcraft-cli` tanpa antarmuka, sama seperti Fase 8–10.

## 1. Ringkasan

| Butir | Hasil | Status |
|---|---|---|
| K-4 edukasi | 10 modul berbahasa Indonesia, berversi, berhash; produksi hanya menampilkan modul yang sudah ditinjau; Asisten menautkan modul di jawaban keselamatan | **selesai teknis; isi menunggu klinisi** |
| K-7 hidangan Indonesia | 45 hidangan dari resep standar × bahan TKPI, porsi umum, resep tersimpan; bukan dari LLM | **selesai teknis; menunggu ahli gizi** |
| K-8 pendamping | tautan baca-saja: ringkasan 7 hari + jam pengingat obat yang belum dikonfirmasi; consent terpisah; bisa dicabut; tanpa catatan mentah | **selesai** |
| K-3 CGM | impor CSV LibreView ke `cgm_readings` terpisah; ringkasan TIR/TAR/TBR deskriptif; tanpa saran dosis | **selesai** |
| K-11 moderasi | lapor alias → antrean tinjau pemilik; sembunyi otomatis setelah 3 pelapor unik; batas laju aksi komunitas | **selesai** |
| D-6 SATUSEHAT | ekspor FHIR R4 (`Bundle` + `Observation` LOINC/UCUM); dokumen kesiapan | **selesai sebatas kesiapan; integrasi butuh faskes mitra** |
| U-2 suara | tombol mikrofon di Asisten dan catatan makan; dikte di perangkat (`onDevice`), audio tidak dikirim ke beOkay | **selesai** |
| U-4 coba dulu | mode coba 7 hari tanpa akun, catatan di penyimpanan terenkripsi perangkat, dipindahkan lewat sinkron setelah membuat akun; persetujuan berlapis di onboarding | **selesai** |

## 2. Rincian

### K-4 modul edukasi

- Isi di `server/src/content/education/modules.ts`: mengenal DMT2/HbA1c, karbohidrat dan porsi, label gizi, hipoglikemia, merawat kaki, saat sakit, puasa Ramadan, obat (kapan bertanya ke dokter), bergerak dengan aman, memeriksa gula darah sendiri dan CGM. Tiap modul diakhiri bagian "Sumber" (ADA Standards of Care 2026; IDF-DAR 2021 untuk Ramadan; konsensus TIR 2019).
- `education_modules` menyimpan setiap versi dengan `content_hash`. API mensinkronkan isi saat mulai. Isi versi yang sudah `REVIEWED` tidak bisa berubah tanpa menaikkan versi.
- Produksi (`EDUCATION_INCLUDE_DRAFTS=false`) hanya menampilkan modul `REVIEWED`. Dev/uji menampilkan draf dengan label "DRAF · menunggu tinjauan klinisi".
- Jawaban keselamatan Asisten (kecuali `SELF_HARM`) kini memuat tautan modul yang relevan alih-alih penolakan kosong.

### K-7 hidangan terkurasi

- `server/src/content/food/curated-dishes.ts` (`curated-dishes-v1`): 45 hidangan, masing-masing resep gram per bahan TKPI dan air/kuah. Komposisi per 100 g = jumlah gizi bahan ÷ berat total. Nilai yang tidak diketahui pada satu bahan membuat nilai hidangan NULL, bukan 0. Tanpa faktor retensi dan susut masak; minyak terserap diperkirakan; lontong dihitung sebagai nasi (TKPI tidak memuat lontong).
- Disimpan di `food_reference` berstatus `curated`, dengan `method`, porsi min/umum/maks, flag `needs_dietitian_review`, dan resep di `food_recipe_items`. Pencarian memberi label "Kurasi beOkay · dari bahan TKPI".
- **Hit rate 20 kueri teratas** (`scripts/food/search-hit-rate.ts`, DB dev, 12 Nov 2026): **9/20 → 20/20**, 12 dari hasil teratas adalah hidangan kurasi. Kriteria "hit" = hasil yang namanya memuat semua kata kueri; kriteria ini longgar (sebelum kurasi "mie goreng" dihitung kena karena "Kerupuk mie kuning goreng"), jadi angka sebelum yang lebih jujur adalah 8/20. "bakso" dan "martabak" kena lewat "Mie bakso" dan "Martabak India" dari TKPI. Daftar 20 kueri disusun pengembang, bukan dari log pencarian pengguna, dan hidangan dipilih untuk menutup daftar itu; ukur ulang dengan kueri nyata selama pilot.
- Daftar baru 45 dari target 150 di gap analysis.

### K-8 pendamping

- Tujuan consent opsional baru `companion_sharing`. Maks. 3 tautan aktif; berlaku 30/90/180 hari; token 32 byte, hanya hash yang disimpan.
- Halaman `/c/:token` menampilkan hari dengan catatan dari 7, menit aktivitas, jumlah pemeriksaan glukosa (tanpa nilai), obat dikonfirmasi dari terjadwal, dan jam pengingat obat yang belum dikonfirmasi ("belum tentu terlewat", sejalan dengan prinsip "tidak diasumsikan diminum atau terlewat"). Nama, nama obat, nama makanan, dan angka glukosa tidak ditampilkan (diuji).
- Menarik consent mencabut semua tautan saat tautan berikutnya dibuka; tautan lama tidak hidup lagi walau consent diberikan ulang.

### K-3 CGM

- Parser `libreview-csv-v1`: header bahasa Inggris LibreView, pemisah koma/titik koma, mg/dL dan mmol/L (koma desimal), tipe rekaman 0 (historis) dan 1 (pindaian), LO/HI dan nilai di luar 20–600 dilewati, format tanggal Y-M-D, M-D-Y, D-M-Y dan AM/PM. Urutan hari/bulan dideteksi; bila ambigu, aplikasi menanyakan.
- Bacaan disimpan di `cgm_readings`, terpisah dari `glucose_observations`, sehingga tidak mengubah statistik glukosa jari yang sudah ada. Impor ulang tidak menggandakan bacaan.
- Ringkasan: persen < 54, 54–69, 70–180, 181–250, > 250 mg/dL; rata-rata; CV; cakupan data (historis 15 menit, cukup bila ≥ 70%). Hanya pindaian → cakupan tidak dihitung dan diberi catatan. Tidak ada GMI dan tidak ada saran dosis.
- Belum: Dexcom Clarity dan pembacaan `BloodGlucoseRecord` CGM dari Health Connect.

### K-11 moderasi komunitas

- Tombol "Laporkan" di papan peringkat; alasan kasar, menyamar, spam, lainnya. Satu laporan per pelapor per alias.
- 3 pelapor unik → alias disembunyikan dari papan peringkat dan pemiliknya diberi notifikasi. Mengganti alias memulihkan dan menutup laporan.
- Antrean pemilik: `scripts/ops/community-reports.ts list|uphold|dismiss`.
- Batas laju: 30 aksi komunitas per 10 menit per akun, 10 laporan per hari. Seperti pembatas lain, batas ini ada di memori proses.

### D-6 FHIR dan SATUSEHAT

Ekspor `GET /api/me/export/fhir`. Pemetaan, yang belum dipetakan, dan syarat SATUSEHAT di [satusehat-readiness.md](../integration/satusehat-readiness.md). Belum divalidasi dengan validator HL7 resmi.

### U-2 input suara

`speech_to_text` dengan `SpeechListenOptions(onDevice: true, localeId: 'id_ID')`. Bila pengenalan suara offline bahasa Indonesia belum terpasang di ponsel, aplikasi menjelaskan cara memasangnya, bukan diam-diam memakai layanan daring. Izin `RECORD_AUDIO`. Teks hasil dikte masuk kolom yang sama, jadi pesan seperti "tadi siang makan nasi goreng" tetap melewati parser kalimat makan yang ada. Tingkat koreksi draf setelah dikte belum diukur.

### U-4 coba dulu dan persetujuan berlapis

- "Coba dulu tanpa akun" di layar selamat datang membuka mode coba: catat glukosa, makan, dan aktivitas di antrean lokal terenkripsi (`flutter_secure_storage`) dengan bentuk payload yang sama dengan sinkron luring. Tidak ada permintaan jaringan.
- Setelah 7 hari, mencatat baru dihentikan; catatan tetap ada sampai pengguna memindahkan atau menghapusnya.
- Setelah membuat akun dan menyelesaikan onboarding, Beranda menawarkan "Pindahkan N catatan" → masuk antrean sinkron akun → `POST /api/me/sync/operations`.
- Onboarding: tujuan wajib tampil di "Diperlukan sekarang"; tujuan opsional dikumpulkan di "Nanti, saat fiturnya dipakai" (tertutup, tetap bisa disetujui sekarang). Persetujuan opsional tetap diminta di fiturnya masing-masing seperti sebelumnya.

## 3. Ukuran

Ditambahkan ke `scripts/analytics/measures.ts` di bagian `ecosystem` (lihat [measures.md](../research/measures.md)): modul dibuka, rasio jawaban keselamatan bertaut modul, pemakaian suara, pemindahan mode coba, catatan pertama ≤ 5 menit sejak akun dibuat, pengguna dengan pendamping aktif.

## 4. Pengujian

| Lapisan | Hasil |
|---|---|
| Backend `bun test` | **402/402** (72 berkas); baru `tests/unit/phase11.test.ts` (17) dan `tests/integration/phase11.test.ts` (9) |
| `tsc --noEmit` | bersih |
| Flutter | `flutter analyze` bersih; **237/237**; baru `phase11_test.dart` (10) |
| Build Android debug | `flutter build apk --debug` berhasil dengan plugin `speech_to_text` dan `file_picker` |

Sapuan keamanan Fase 9 (IDOR untuk semua rute GET ber-parameter, 401 tanpa login untuk semua `/api/me/*`) otomatis mencakup rute baru dan tetap lulus.

## 5. Yang harus dilakukan pemilik

1. **Klinisi** meninjau 10 modul (paket tinjauan §6b, pertanyaan 12–13), lalu `scripts/ops/education.ts review <key> 1 "<nama>"` per modul yang disetujui. Sampai itu, produksi tidak menampilkan modul.
2. **Ahli gizi** meninjau 45 resep dan porsi (pertanyaan 14); hapus flag `needs_dietitian_review` hanya lewat perubahan data dan versi baru.
3. Tinjauan hukum teks consent `companion_sharing`.
4. Jajaki faskes mitra untuk D-6; validasi ekspor FHIR dengan HL7 validator.
5. Uji dikte di ponsel nyata dengan paket suara offline bahasa Indonesia; emulator tidak punya mikrofon.

## 6. Rollback

Migrasi `20261112180000_p11_ecosystem` hanya menambah tabel, kolom nullable, dan memperluas CHECK. Mematikan tanpa rollback: `feature-flag.ts set companion off`, `set cgm off`; modul edukasi bisa ditarik dengan `education.ts retire`; hidangan kurasi bisa dihapus dengan `DELETE FROM food_reference WHERE status = 'curated'` (resep ikut terhapus).
