# Riset grafik tren (Wawasan) — 9 Nov 2026

Permintaan: grafik statistik yang interaktif, menarik, dan membawa efek "semakin baik dari hari ke hari".

## 1. Apa yang dibutuhkan (hasil riset → keputusan)

**Data.** Satu endpoint tren (`GET /api/me/trends?days=7|14|30|90`) yang dihitung di server dari tabel sumber, per hari menurut zona waktu pengguna, ditambah periode pembanding sama panjang. Satu kali panggilan untuk semua grafik (filter di satu baris menskop semuanya). Tanpa tabel baru.

**Glukosa — apa yang TIDAK boleh digambar.** Konsensus internasional *time in range* mensyaratkan CGM aktif ≥70% selama 14 hari ([ATTD consensus, PMC6973648](https://pmc.ncbi.nlm.nih.gov/articles/PMC6973648)). beOkay memuat pengukuran glukometer manual yang jarang, jadi *time in range*, GMI/estimasi A1c, dan pita "rentang target" tidak valid dan ditolak. Yang digambar: kapsul rentang harian (min–maks) dan titik pengukuran, tanpa garis penghubung antar-hari yang jarang, tanpa warna baik/buruk, dengan jumlah pengukuran di tooltip. Hanya data `user_reported` (yang ditandai tinjau/arsip dikecualikan).

**Efek "semakin baik" — apa yang aman.** Perbaikan hanya diklaim pada **perilaku sendiri** (konsistensi mencatat, menit aktivitas, rekor pribadi), dibandingkan dengan periode sebelumnya milik pengguna sendiri, dan hanya bila kedua periode punya data (tidak diketahui ≠ nol → tidak ada klaim). Nilai glukosa tidak pernah dinilai membaik/memburuk. Rangkaian hari beruntun: sumber yang saya temukan (blog; satu ringkasan studi Journal of Consumer Research yang belum saya verifikasi ke makalahnya) menyebut bahwa rangkaian putus yang disorot menurunkan keberlanjutan pemakaian dan memicu "what-the-hell effect". Maka: angka utama adalah *"N dari M hari tercatat"* (tidak pernah mereset ke nol), rangkaian hanya muncul sebagai catatan positif bila ≥2 hari, dan rangkaian yang putus tidak pernah ditampilkan. Penurunan dibandingkan periode lalu tidak diberi catatan — hanya angka netral di tooltip.

**Efek visual.** Animasi tumbuh dari nol (bar), kapsul muncul berurutan, rekor pribadi diberi penanda; semuanya mati bila pengguna mengaktifkan "kurangi gerak". Haptic ringan saat geser berpindah hari.

## 2. Bentuk grafik (aturan skill dataviz)

| Pekerjaan | Bentuk | Warna |
|---|---|---|
| Konsistensi mencatat | strip kalender (satu sel per hari, terisi = ada catatan, kosong = tidak tercatat) | satu hue (brand) |
| Aktivitas | batang dari nol; periode sebelumnya sebagai batang abu tipis di belakang (emphasis: sekarang = hue, lalu = abu) | emerald + abu |
| Glukosa | kapsul min–maks per hari + titik; tanpa pita target, tanpa garis antar-hari | biru-aqua |
| Makan | batang hitungan makan; karbohidrat tercatat (g) di tooltip dengan cakupan LENGKAP/SEBAGIAN/TIDAK DIKETAHUI | hijau daun |
| Obat | titik konfirmasi per hari (diminum/dilewati) — tanpa persentase kepatuhan | ungu |

Satu seri per grafik → tidak ada palet kategorikal; warna domain sama dengan seluruh aplikasi dan selalu bersama ikon + label. Tanpa sumbu ganda, tanpa donat, tanpa angka di setiap titik (hanya ekstrem + tooltip).

## 3. Interaksi

- Filter rentang (7/14/30/90 hari) satu baris di atas semua grafik; semua grafik ikut berubah.
- Geser jari / ketuk → garis pemandu menempel ke hari terdekat + tooltip (nilai besar, label kecil); area sentuh ≥ lebar slot (≥ 24 dp), bukan hanya piksel batang.
- Tooltip tidak pernah jadi satu-satunya jalan: setiap grafik punya **"Lihat sebagai tabel"** dan label semantik per hari untuk TalkBack (`CustomPainter.semanticsBuilder`).
- Saat ganti rentang, grafik lama bertahan setengah transparan sampai data baru tiba (tanpa skeleton/lompatan tata letak).
- Pustaka: `CustomPainter` buatan sendiri (bukan `fl_chart`) agar aturan "tidak ada garis antar-hari jarang" dan semantik per hari terkendali; tidak ada dependensi baru.

## 4. Verifikasi yang direncanakan
Tes unit model (7), tes integrasi endpoint (kapsul, pengecualian review/arsip, kepemilikan, consent), tes widget interaksi (geser → tooltip, tabel, ganti rentang), dan emulator Appium.
