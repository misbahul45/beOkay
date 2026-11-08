# P0 UI Refresh v2 — audit, riset, desain, hasil

9 November 2026 (WIB). Menggantikan bagian "Keputusan desain" di `p0-ui-research.md` untuk ukuran dan tata letak; riset sumber di dokumen itu tetap berlaku.

## 1. Audit UI di HP (Redmi 2409BRN2CY, 720×1640, density 320)

Setiap layar dibuka di perangkat dan ditangkap. Masalah yang berulang:

| # | Temuan | Contoh layar |
|---|---|---|
| 1 | **Judul ganda**: judul AppBar + headline besar yang mengulang topik | semua form (Catat glukosa/aktivitas/makanan), Ubah profil, Ubah profil kesehatan, Persetujuan |
| 2 | **Skala tipe terlalu besar**: headline 30, body 16, tombol 52, input 56, nav 72, padding halaman 20 | semua |
| 3 | **Kartu domain 250px tinggi** per domain pada hari kosong (teks + tombol penuh + tautan) | Beranda |
| 4 | **Aksi berupa teks telanjang** ("Riwayat", "Filter tanggal", "Ubah satuan tampilan") tanpa bentuk tombol | Beranda, semua Riwayat |
| 5 | **Keadaan kosong bergaya headline** ("Belum ada durasi yang dapat diringkas.") sehingga terbaca seperti data | Riwayat aktivitas |
| 6 | **Hero editorial gelap + dua tombol penuh** sebelum konten | Riwayat aktivitas |
| 7 | **Paragraf bantu panjang** (zona waktu, satuan, koneksi) di tiap form | form glukosa/aktivitas/makanan |
| 8 | **Baris pengaturan membungkus**: label 2–3 baris karena nilai ikut berebut lebar | Profil |
| 9 | **Email patah per karakter** (`ujihp179/4155914/@beoka/y.local`) | Keamanan akun |
| 10 | Kartu ringkasan berisi paragraf metode panjang | Riwayat glukosa |

Catatan metode: beberapa tangkapan layar di tengah sesi terlihat lebih besar karena preferensi "Ukuran teks" akun uji berubah menjadi *Besar* akibat tap koordinat yang meleset. Sudah dikembalikan ke "Ikuti sistem" lewat API dan semua tangkapan akhir diambil pada pengaturan itu.

## 2. Riset

Sumber ringkas (tingkat bukti dicantumkan):

| Topik | Temuan | Bukti |
|---|---|---|
| Skala tipe Material 3 | headline-small 24sp, title-medium 16sp, body-medium 14sp, label-large 14sp (500) | implementasi pihak ketiga ([bevy_material_ui](https://docs.rs/crate/bevy_material_ui/latest/source/src/typography.rs), [handbook CFDesktop](https://awesome-embedded-learning-studio.github.io/CFDesktop/HandBook/ui/material/cfmaterial_fonttype)); halaman resmi m3.material.io tidak berhasil diambil |
| Apple HIG | ukuran default iOS 17pt, minimum 11pt | [Apple HIG typography](https://developer.apple.com/design/human-interface-guidelines/typography.md) (resmi). Ukuran Title/Footnote tidak terverifikasi |
| Inter di UI | satu optical size → tracking manual: negatif pada judul besar (≈ −1…−3%), 0 pada isi, positif kecil untuk label kapital kecil; line-height 1.4–1.65 untuk isi | panduan merek ([GoCardless](https://brand.gocardless.com/typography)), referensi optical sizing; bukan spesifikasi resmi Inter |
| Form mobile | label di atas kolom tunggal; jangan jadikan placeholder sebagai label | [Baymard](https://baymard.com/blog/mobile-form-usability-label-position), [Aon design system](https://designsystem.aon.com/components-3/form-elements/form-inputs), UW |
| Target sentuh | 48dp (Material); WCAG 2.2 SC 2.5.8 AA = 24px | [W3C](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html) |
| Pengguna kesehatan lebih tua | teks 14pt sering dianggap terlalu kecil; konsisten, label pada ikon, kurangi beban kognitif | blog/jurnal kecil ([Orangesoft](https://orangesoft.co/blog/guide-to-designing-healthcare-apps-for-seniors) dll.); bukti lemah |

**Ketegangan yang disadari:** diminta lebih kecil, tetapi riset kesehatan menyarankan jangan terlalu kecil. Keputusan: pengurangan *moderat* (body 16→15, secondary 14→13, caption 12.5→12, tidak ada teks < 11sp) dan kekompakan dicapai terutama lewat **tata letak** (menghapus judul ganda, kartu ringkas, paragraf dipindah ke bagian yang bisa dibuka), bukan dengan mengecilkan teks secara ekstrem. Pengguna tetap bisa menaikkan lewat Pengaturan → Ukuran teks.

## 3. Desain (FigCraft)

`design/beOkay-ui.figcraft` halaman **"16 — UI Refresh v2"** (dihasilkan lewat `figcraft-cli mcp --attach 7979` terhadap aplikasi FigCraft yang berjalan): skala tipografi + 7 layar acuan 360×780 (Beranda berisi dan kosong, Catatan, Wawasan, Profil, Form Catat glukosa, Riwayat glukosa). Ikhtisar PNG: `design/ui-refresh-v2-overview.png`.

Catatan: tool MCP `figcraft` tidak muncul di sesi Claude ini (koneksi MCP hanya dibuat saat sesi mulai); klien MCP stdio yang sama dengan server `figcraft-cli mcp` dipakai langsung. Ikon di frame memakai glyph/emoji sebagai penanda; aplikasi memakai Material Icons.

### Token v2 (lama → baru)

| Token | Lama | Baru |
|---|---|---|
| display / headline / heading | 38 / 30 / 24 | 30 / 24 / 18 |
| title / body | 17 / 16 | 16 / 15 |
| secondary / caption / overline | 14 / 12.5 / 11.5 | 13 / 12 / 11 (+0.8 tracking) |
| padding halaman / kartu | 20 / 16 | 16 / 14 |
| radius kartu / input | 24 / 16 | 20 / 14 |
| tombol / input | 52 / 56 | 48 / 48 |
| chip | 48 (tampil) | 36 tampil, area sentuh 48 |
| nav bar / baris pengaturan / tile | 72 / 60 / 72 | 64 / 52 / 60 |

### Pola tata letak

- Satu judul per layar: tab memakai headline; subhalaman hanya judul AppBar.
- `MetricCard` ringkas: ikon · judul · nilai/keterangan · tombol "+" (48dp area sentuh); ketuk kartu = riwayat. Keadaan kosong satu baris, bukan paragraf.
- `TextButton` global bergaya tonal (terlihat sebagai tombol). Pengecualian di latar gelap (Welcome) ditransparankan.
- Nilai panjang pada baris pengaturan dipindah ke bawah judul; judul dipotong dengan elipsis alih-alih patah per karakter.
- Paragraf bantu form dipersingkat; metode dan cakupan ringkasan dipindah ke bagian yang bisa dibuka.

## 4. Hasil

Terverifikasi langsung di HP (ukuran teks sistem): Beranda, Catatan, Wawasan, Profil, Quick Record, form Catat glukosa/aktivitas, Riwayat glukosa/aktivitas, Keamanan akun, Persetujuan data, Pengaturan, dialog Keluar, Welcome, Login, Daftar, Lupa kata sandi (halaman terakhir hanya diambil dari tautan "Lupa kata sandi?" pada Login).

Contoh ukuran: Beranda hari kosong sebelumnya ±3 layar scroll untuk melihat semua kartu; kini kartu Glukosa/Nutrisi/Aktivitas + "Sedang disiapkan" tampil dalam satu layar. Profil dari ±2.5 layar menjadi ±1.3.

Regresi yang tertangkap saat verifikasi dan diperbaiki: teks Welcome tak terbaca (akibat tema TextButton tonal), email patah per karakter, label baris pengaturan membungkus.

Tes: `flutter analyze` bersih; `flutter test` 59 lulus. Asersi yang diubah mengikuti teks baru (judul AppBar sebagai satu-satunya judul, "Email terverifikasi", salinan kosong yang lebih pendek), bukan dilemahkan.

## 5. Belum diverifikasi

Layar onboarding (Intro, Persetujuan awal, Profil, Kesehatan, Preferensi, Selesai), layar Detail (glukosa/makanan/aktivitas), Riwayat makanan, Ringkasan mingguan, form Makanan setelah perubahan terakhir, Daftar → Verifikasi email, dark mode, landscape, TalkBack, perangkat selain Redmi ini, dan skala teks 2.0 setelah refresh v2 (skala 2.0 diuji sebelum refresh; perlu diuji ulang). Perubahan token memengaruhi semua halaman tersebut, jadi perlu satu putaran pengecekan visual.
