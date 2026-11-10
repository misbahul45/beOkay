# P1 — audit kesiapan dan status (9 November 2026)

> **Koreksi (9 Nov 2026, Irisan 3):** kesimpulan di bagian ini ("angka tidak terbaca andal, tidak diingest") ternyata terlalu pesimis. OCR `mistral-ocr-latest` membaca tabel dengan baik dan 91,6% baris lolos pemeriksaan konsistensi internal. TKPI kini diingest sebagai `food_reference` — lihat "Irisan 3" di bawah. Teks asli dipertahankan sebagai riwayat keputusan.

## Sumber data Tabel Komposisi Pangan Indonesia — temuan penting (riwayat)

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

## Irisan 3 — referensi TKPI, preferensi, pengingat, ekspor, impor aktivitas, insight (9 Nov 2026)

Backend selesai dan teruji di Docker (DB uji terisolasi). **UI Flutter untuk item-item ini belum dikerjakan** (lihat "Batas" di bawah).

| Kemampuan | Status | Bukti |
|---|---|---|
| **Referensi TKPI (RAG pangan)**: OCR 140 hlm → parser → validator Atwater + jumlah proksimat → tabel `food_reference` (pgvector) | VERIFIED backend | 1.132 baris di bab 4; **1.037 `verified_auto` (91,6%)**, 95 `needs_review` (dikecualikan dari pencarian dan kalkulator). `tests/unit/tkpi-parser.test.ts`, `tests/unit/food-reference.test.ts`, `tests/integration/food-reference.test.ts` |
| Embedding `mistral-embed` (1024 dimensi) untuk 1.037 nama | VERIFIED (dijalankan nyata) | `scripts/tkpi/ingest.ts`; klien memvalidasi dimensi/NaN/status |
| Pencarian hibrida: pg_trgm (leksikal) + cosine pgvector (semantik) + Reciprocal Rank Fusion; kembali ke leksikal bila embedding gagal | VERIFIED | tes integrasi dengan embedder palsu untuk jalur semantik; jalur leksikal-saja lewat API |
| Ambang kemiripan 0,75 | **Heuristik**, bukan evaluasi terukur | 14 kueri nyata: relevan puncak 0,77–0,91; tak bermakna ("laptop", "mobil balap", "xyz qwerty") 0,64–0,72 |
| Integrasi ke Food Discovery (`reference` pada `/foods/discover`, `GET /foods/reference`) | VERIFIED | tes integrasi |
| PDF sumber diunggah ke UploadThing | DONE (akun demo) | key `uEc5gvzB5LqYVSTRtJkBz5xYkemF8MfpOwvTPXs790WCoaGj`, 6.270.131 B, SHA-256 `cc4f26dd…de6c12b`; token tidak disimpan di berkas ter-track |
| **Preferensi/alergi/pembatasan makanan** (`food_preferences`, strict vs soft) | VERIFIED backend | CRUD berversi, idempoten, terisolasi, consent; `tests/integration/food-preferences.test.ts` |
| Pencocokan preferensi pada hasil pencarian (`preferenceCheck`, `hideExcluded`) | VERIFIED | **Heuristik berbasis nama**: tidak ada hasil yang berarti "aman"; `NO_MATCH_FOUND` disertai catatan bahan tidak diketahui |
| **Pengingat** (`reminders`: aturan jam lokal + hari, kejadian mendatang DST-aman) | VERIFIED backend | `tests/unit/reminders.test.ts` (Jakarta, New York, celah DST), integrasi. Server tidak mengirim apa pun; **penjadwalan notifikasi di perangkat belum ada** |
| Teks layar kunci generik (tanpa nama obat/nilai) | VERIFIED | tes unit |
| Perbaikan bug lama `zonedToUtc`: jam di celah DST dimundurkan 1 jam padahal komentar menyatakan dimajukan | FIXED + tes regresi | `medication.test.ts` (tidak berdampak pada WIB karena tanpa DST) |
| **Ekspor data** `GET /api/me/export` | VERIFIED | hanya data sendiri; tanpa sesi/akun/hash internal; tetap bisa setelah consent ditarik; 5/jam; diaudit |
| **Impor aktivitas perangkat** `POST /api/me/activities/import` (`health_connect`/`apple_health`) | VERIFIED backend (payload sintetis) | idempoten per `externalId`; `device_reported`; tabrakan waktu → `needs_review` (tidak dihitung); CHECK DB. **Pembacaan Health Connect di Flutter belum ada** |
| **Insight kontekstual** `GET /api/me/insights/contextual` | VERIFIED | aturan berversi `contextual-rules-v1`, maks 3, tanpa penilaian nilai glukosa; `tests/unit/contextual.test.ts` |
| Pencarian web terkontrol `GET /api/me/foods/web-search` | VERIFIED dengan `fetch` palsu; **nonaktif tanpa `BRAVE_API_KEY`** | host dipaku, https tanpa kredensial/IP/host lokal, tag HTML dibuang, hasil `usableForNutrition:false` |
| Ringkasan harian dipersistensi (`summary_projections`, kind `daily`) | VERIFIED | `tests/integration/summaries.test.ts` |
| Koreksi data saat offline diantrekan (Flutter) | VERIFIED (tes unit/widget) | `offline_sync_test.dart`; PATCH → operasi `update` dengan `expectedVersion`; koreksi tertunda untuk catatan sama digabung; belum diuji di emulator |

### Batas yang harus dibaca apa adanya

- `verified_auto` = **konsisten secara internal**, bukan diperiksa manusia. Kesalahan OCR yang kebetulan menjaga Atwater tidak tertangkap. Pengguna melihat sumber "TKPI (OCR, pemeriksaan otomatis)". Hanya makro yang diambil (air, energi, protein, lemak, karbohidrat, serat, abu); mikro tidak diingest.
- Bab dengan tingkat lolos terendah: 4.11 Gula/Konfeksioneri 10/18, 4.3 Kacang 123/138.
- Pencocokan alergi berbasis nama. Itu bantuan, **bukan jaminan keamanan**.
- Tidak diuji: Health Connect/HealthKit di perangkat, notifikasi lokal, Open Food Facts ke jaringan nyata untuk pencarian teks, Brave dengan kunci nyata.
- **UI Flutter P1 (ditambahkan setelahnya, lihat "Irisan 3b" di bawah).** Layar-layar itu dibuat **tanpa desain FigCraft** karena MCP `figcraft` gagal tersambung (`CONNECTION_CLOSED`); pengguna meminta lanjut setelah mengetahui batas itu. Komponen dan token desain yang sudah ada dipakai ulang, tidak ada bahasa visual baru. Desain FigCraft untuk layar-layar ini tetap perlu dibuat dan ditinjau, lalu UI disesuaikan.
- Bruno folder `18` dan `19` ditambahkan tetapi **belum dijalankan** lewat Bruno CLI.

## Irisan 3b — UI Flutter untuk fitur Irisan 3 (9 Nov 2026)

| Layar / perilaku | Status | Bukti |
|---|---|---|
| Alergi & preferensi makanan (Profil → Rutinitas): daftar per jenis, tambah (pilihan cepat/tulis sendiri), hapus; peringatan "hanya bantuan, bukan jaminan" | VERIFIED (tes widget) | `food_preferences_screen_test.dart` |
| Pemilih makanan: bagian "Referensi TKPI" + label sumber; peringatan alergi/tidak suka per hasil; konfirmasi sebelum memakai hasil yang cocok kendala keras; kegagalan tambahan tidak memblokir pencarian utama | VERIFIED (tes widget) | `food_preferences_test.dart` |
| Kartu "Catatan untukmu" di Wawasan (insight kontekstual; disembunyikan bila kosong/gagal) | VERIFIED (tes widget) | `contextual_card_test.dart` |
| Pengingat: daftar, tambah/ubah/hapus, saklar; penjadwal notifikasi lokal (mode inexact); sinkron saat masuk/dibuka kembali; semua dibatalkan saat keluar akun, sesi habis, atau consent kesehatan ditarik | VERIFIED logika & layar (penjadwal palsu); **notifikasi nyata belum diuji di perangkat/emulator** | `reminders_test.dart` |
| Unduh data saya (Persetujuan Data): tulis berkas sementara, bagikan lewat lembar bagikan sistem, hapus berkas | VERIFIED (tes dengan pembagi palsu); lembar bagikan nyata belum dicoba | `export_test.dart` |
| Ukuran rumah tangga di editor item makan: pilih ukuran milik makanan itu, gram = jumlah × gram per ukuran (dengan dasar ditimbang/perkiraan), tambah ukuran; tanpa ukuran = tidak ada konversi karangan | VERIFIED (tes widget) | `household_measure_test.dart` |
| Impor aktivitas dari Health Connect (Android): hanya atas tombol, baca sesi olahraga 30 hari, izin read-only, kirim ke endpoint impor | VERIFIED logika/pemetaan/UI dengan sumber palsu; **pembacaan Health Connect nyata belum diuji** (tidak ada perangkat/emulator dengan data); **iOS/HealthKit tidak didukung** (belum dikonfigurasi) | `device_import_test.dart` |
| Koreksi data saat offline | lihat Irisan 3 | `offline_sync_test.dart` |

Konfigurasi Android yang berubah: `compileSdk` ≥ 37, core library desugaring, `minSdk` ≥ 26 (Health Connect), `MainActivity` → `FlutterFragmentActivity`, izin `POST_NOTIFICATIONS`/`RECEIVE_BOOT_COMPLETED`/`READ_EXERCISE`/`READ_DISTANCE`/`READ_STEPS`, receiver notifikasi terjadwal, `activity-alias` kebijakan privasi Health Connect, `<queries>`. Plugin notifikasi dipaku ke `^22.3.3` karena v23 menarik `androidx.core 1.19` yang butuh AGP ≥ 9.1 (proyek memakai 9.0.1) — build gagal ditemukan dan diperbaiki.

Verifikasi build: `flutter build apk --debug` **berhasil** dengan seluruh konfigurasi di atas (APK debug terbentuk). Peringatan yang tersisa: plugin `health` masih memakai Kotlin Gradle Plugin lama; Flutter memperingatkan versi mendatang akan gagal membangun plugin seperti itu, jadi `health` perlu diperbarui saat tersedia versi yang mendukung Built-in Kotlin. Build berhasil bukan berarti fitur sudah dijalankan di perangkat.

## Verifikasi di emulator (9 Nov 2026, AVD `Pixel_4`, Android API 37, API dev lewat `adb reverse`)

Dijalankan dengan APK debug hasil `flutter build apk --debug` dan dikendalikan lewat `adb` (bukan Appium).

| Yang diuji | Hasil |
|---|---|
| Pengingat: tambah "Uji notifikasi" 13:16 lewat UI | Aturan tersimpan di server dan tampil di daftar |
| Izin notifikasi Android (API 33+) | Dialog sistem asli muncul saat pengingat pertama dibuat; diizinkan |
| Penjadwalan | `dumpsys alarm` memuat alarm `RTC_WAKEUP` untuk `com.example.app` (13:16 hari ini, lalu 7 hari ke depan) dari kejadian yang dihitung server |
| Notifikasi muncul | Muncul 13:17:56 untuk jadwal 13:16 (dalam jendela inexact yang dinyatakan ±2 menit). Judul "Pengingat beOkay", isi "Buka beOkay untuk mencatat."; judul buatan pengguna **tidak** bocor; `visibility=PRIVATE`, kanal `beokay_reminders` |
| Health Connect: tombol impor → izin → baca | Layar izin Health Connect asli muncul dan hanya meminta **Activity (baca)**; setelah diizinkan, aplikasi melapor "Tidak ada sesi olahraga … 30 hari terakhir" (emulator tidak punya data olahraga) |
| Alergi: tambah "kacang" lewat pilihan cepat | Tersimpan; tampil sebagai kendala keras |
| Pemilih makanan: cari "kacang" | Bagian "Referensi TKPI" dari basis data dev (pencarian hibrida, data nyata) dengan label sumber dan 533/118/331 kkal per 100 g; setiap hasil diberi peringatan merah "cocok dengan kacang (dugaan dari nama)" |

**Belum teruji di emulator:** impor sesi olahraga dengan data nyata (tidak ada data di Health Connect emulator; jalur ini hanya teruji dengan sumber palsu), lembar bagikan untuk ekspor, konfirmasi "Tetap gunakan", ukuran rumah tangga, kartu insight di Wawasan, koreksi offline, notifikasi setelah reboot, dan perangkat fisik.

Temuan kosmetik dari uji ini: nama aplikasi tampil "app" (diperbaiki menjadi "beOkay" di manifest; perlu build ulang) dan ikon notifikasi/launcher masih bawaan Flutter (belum diganti). Label alergi dari pilihan cepat tampil huruf kecil (diperbaiki di klien; perlu build ulang). Data uji yang dibuat di akun dev (satu pengingat, satu alergi) sudah dihapus dari DB dev.

### Pembaruan: nama dan logo aplikasi (9 Nov 2026)

- Nama tampilan menjadi **beOkay** di Android (`android:label`), iOS (`CFBundleDisplayName`/`CFBundleName`), dan web (`index.html`, `manifest.json`).
- Ikon aplikasi dibuat dari `assets/images/logo_mark.png` dengan `flutter_launcher_icons` (konfigurasi di `pubspec.yaml`; sumber di `assets/icon/`): ikon adaptif Android (latar mint `#F1F8F6`), ikon iOS tanpa alfa, ikon web. Ikon status-bar notifikasi dibuat monokrom (`drawable-*/ic_stat_beokay.png`) dengan `res/raw/keep.xml` agar tidak dibuang saat rilis; penjadwal memakainya.
- **Diverifikasi di emulator** setelah build ulang: header Recents menampilkan "beOkay" dengan logo beOkay, dan notifikasi pengingat menampilkan "beOkay" dengan logo beOkay. Koreksi sebelumnya (label alergi berhuruf kapital) ikut terpasang.
- **Belum diverifikasi:** tampilan ikon iOS dan web (dihasilkan tetapi tidak dijalankan), mode ikon bertema (monochrome) Android 13+, dan glyph status-bar monokrom pada layar status yang tersempit (Android 16 menampilkan ikon aplikasi pada kartu notifikasi, bukan siluet). Ikon sumber diturunkan dari logo yang sudah ada, bukan desain ikon khusus; penyesuaian ruang aman adaptif (60%) belum ditinjau secara visual oleh desainer.

## Keputusan cakupan platform (9 Nov 2026): Android saja

Pemilik produk memutuskan cukup **Android**, bukan iOS, dan memakai kit Google. Akibatnya:
- Aktivitas perangkat = **Health Connect** (Android, paket `health`; baca `READ_EXERCISE`/`READ_DISTANCE`/`READ_STEPS`). **HealthKit/Apple Health tidak dikerjakan** dan bukan lagi kekurangan P1. Server masih menerima nilai sumber `apple_health` pada endpoint impor (tidak dipakai klien); boleh dihapus bila ingin ketat.
- Notifikasi = notifikasi lokal Android + **FCM** (kit Google). Konfigurasi APNs/iOS tidak diperlukan.
- Ikon, nama, dan berkas iOS/web yang sempat dihasilkan alat ikon tetap ada di repo tetapi tidak diuji dan tidak menjadi syarat rilis.
- Yang tersisa di sisi Android untuk push: mendaftarkan aplikasi Android beOkay di proyek Firebase dan menaruh `google-services.json` (lihat `docs/architecture/push-notifications.md`).
