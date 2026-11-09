# P1 — audit kesiapan dan status (9 November 2026)

## Sumber data Tabel Komposisi Pangan Indonesia — temuan penting

`Downloads/Tabel Komposisi Pangan Indonesia.pdf` (140 halaman) **adalah hasil pindai gambar**, bukan teks:

- Setiap halaman tabel berisi satu gambar JPEG 841×595 (72 ppi); lapisan teks PDF hanya berisi watermark ("KEMENKES RI").
- Tabel memuat ±20 kolom zat gizi per baris dengan font kecil; sel yang disorot biru tidak terbaca.
- OCR pada resolusi ini menghasilkan angka yang tidak dapat diverifikasi. Memasukkannya ke tabel gizi akan menjadi data kesehatan yang tampak resmi tetapi mungkin salah.

**Keputusan:** angka dari PDF ini **tidak** dimasukkan ke basis data dan **tidak** diindeks untuk RAG. Syarat untuk memakainya: (a) berkas sumber digital atau pindaian ≥ 300 ppi, atau (b) verifikasi manual per baris dengan status `reference_verified`. Skema P1 sudah menyiapkan provenans (`source`, `sourceVersion`, `status`) sehingga baris terverifikasi dapat dimasukkan kelak tanpa mengubah kalkulator. Embedding (`mistral-embed`) tetap hanya relevan untuk pencarian nama makanan setelah daftar itu ada.

## Yang dibangun pada tahap ini

| Kemampuan | Status | Bukti |
|---|---|---|
| Kalkulator gizi/porsi deterministik (Decimal, cakupan UNKNOWN/PARTIAL/COMPLETE) | VERIFIED | `tests/unit/food-discovery.test.ts`, `tests/integration/food-calc.test.ts` |
| Ukuran rumah tangga per makanan per pengguna (`food_portion_measures`) | VERIFIED | migrasi `20261109040000`; tes integrasi (kepemilikan, validasi) |
| Pencarian makanan lokal-dahulu (`GET /api/me/foods/discover`) | VERIFIED | tes integrasi + unit |
| Adapter Open Food Facts (host tetap, tanpa redirect, batas waktu 5 dtk dan 1 MB) | VERIFIED dengan fixture; **tidak diuji ke jaringan nyata** | tes unit dengan `fetch` palsu |
| Adapter USDA FoodData Central | IMPLEMENTED; nonaktif tanpa `USDA_API_KEY` (tidak ada kunci) | tes unit: `PROVIDER_NOT_CONFIGURED`, kunci hanya di header |
| Pencarian sumber luar hanya atas permintaan eksplisit; batas 20/10 menit per pengguna; kegagalan penyedia tidak menggagalkan hasil lokal | VERIFIED | tes unit layanan |
| Barcode (validasi GTIN + pencarian Open Food Facts) — API | VERIFIED dengan fixture | tes unit/integrasi |
| UI: "Cari juga di sumber luar" di pemilih makanan; hasil disimpan sebagai estimasi, nilai kosong tetap kosong | VERIFIED (tes widget) | `test/flows/food_external_test.dart` |
| Bruno `15 - Food Discovery and Calculator` | ADDED | folder Bruno |

## Belum dikerjakan

- Pemindaian barcode dengan kamera (butuh plugin kamera dan uji perangkat), foto makanan.
- Pencarian web terkontrol (butuh kunci Brave/Tavily; kunci Tavily di `reducera` tidak disalin karena di luar izin).
- Preferensi makanan dan alternatif makanan.
- Health Connect (Android) / HealthKit (tidak bisa diverifikasi di mesin ini).
- Pengingat, insight kontekstual, ekspor data.
- UI untuk mengelola ukuran porsi dan memanggil kalkulator dari form makanan (API siap).

## Keamanan penyedia luar

Host penyedia ditulis tetap di kode (bukan dari input pengguna), HTTPS wajib, `redirect: "error"`, batas waktu dan ukuran balasan, nilai tak masuk akal menjadi `null` + flag, kunci API hanya lewat header dan tidak pernah di URL atau log. Teks pencarian dikirim ke pihak ketiga hanya setelah pengguna menekan tombol sumber luar, dengan keterangan di layar.

## Irisan 2 — pemindaian (9 Nov 2026)

**Model dipilih berdasarkan tugas, bukan satu model untuk semuanya.** Daftar model diperiksa langsung dari akun Mistral yang diizinkan (`GET /v1/models`): `mistral-ocr-latest` (OCR, bukan chat) dan model chat ber-vision (`mistral-small-latest`, dst.).

| Tugas | Model | Mengapa | Batas yang dipaksa |
|---|---|---|---|
| Label gizi kemasan | `mistral-ocr-latest` (env `MISTRAL_OCR_MODEL`) | OCR dokumen khusus; keluaran markdown tabel | Model hanya membaca **teks**. Angka diambil parser deterministik (`label-parser.ts`); dasar nilai (per 100 g / per sajian) hanya ditetapkan bila tidak ambigu; tanpa takaran saji gram → per 100 g tetap null |
| Foto makanan | `mistral-small-latest` (env `MISTRAL_VISION_MODEL`) | Vision umum, murah | Hanya **nama** kandidat + tingkat keyakinan; prompt melarang kalori/berat; keluaran divalidasi skema Zod; teks di dalam gambar diperlakukan sebagai data |
| Kode batang | ML Kit di perangkat (`mobile_scanner`) | Tidak perlu jaringan atau foto keluar | Validasi digit GTIN di klien dan server sebelum Open Food Facts dipanggil |

Alasan foto makanan tidak menghasilkan kalori: riset (Nutrients 2025 tentang ChatGPT-5; ringkasan studi 52 makanan; CVPR 2026 workshop) menempatkan estimasi porsi sebagai sumber galat terbesar, dan galat meningkat pada porsi besar dan hidangan campur. Maka foto hanya membantu **mengenali nama**; berat dan gizi tetap dari pengguna (satuan rumah tangga, gram) lewat kalkulator deterministik.

Privasi: tiap pengiriman foto didahului dialog persetujuan (tidak diingat); foto diperkecil di perangkat (≤1280 px, JPEG) sehingga EXIF hilang; server menerima biner ≤1,5 MB, memeriksa magic byte, tidak menulis ke disk/DB; log hanya metadata (ukuran, jumlah karakter OCR, nilai terbaca). Batas 10 pindai/10 menit/pengguna. Tanpa kunci → hasil `PROVIDER_NOT_CONFIGURED`, tanpa panggilan jaringan.

Verifikasi: 10 tes unit parser, 8 tes unit service (fetch palsu), 1 tes integrasi endpoint, 6 tes widget; **emulator**: label sintetis (galeri) → OCR Mistral nyata → 400/20/10/60/6,7 per 100 g → disimpan `estimated` ke DB; kode 3017620422003 → Open Food Facts nyata → layar periksa. **Belum teruji:** foto makanan nyata (hanya gambar non-makanan → `isFood:false`), pemindaian kamera pada kode batang fisik (emulator memakai adegan virtual; kode dimasukkan manual), label cetak berbagai format.
