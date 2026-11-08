# Core Health — spesifikasi desain fallback

Pembaruan Slice 2: [Nutrition FigCraft spec](nutrition-figcraft-spec.md) dan halaman native `10 — Nutrition` sudah dibuat, dirender dan diperiksa melalui engine FigCraft headless. Keterbatasan MCP pada catatan Slice 1 di bawah tetap berlaku untuk desktop attach, bukan untuk akses headless native yang sekarang tersedia.

Slice 1: Today Foundation. Dibuat sebelum implementasi UI. FigCraft MCP tidak tersedia; arsip `design/beOkay-ui.figcraft` dipertahankan. Dokumen ini bukan klaim file FigCraft baru atau persetujuan desain pengguna.

Gunakan tema Flutter existing: Inter, Ice Blue #C8D9E8, Off White #F6F8FA, Charcoal #171B20, Slate Gray #788996 (dekoratif), Steel Blue #A8BDCE, putih. Teks pendukung memakai token slateText existing yang lebih gelap; jangan gunakan slate dekoratif untuk teks kecil. Reuse semantic info/warning/error/focus existing.

Komposisi Today: SafeArea → scroll vertikal padding 20 sesuai token existing → greeting nama dan akses profil → tanggal lokal preferensi dan sapaan waktu → charcoal editorial card “Setiap catatan membantu.” → daftar ringkasan Glukosa, Nutrisi, Aktivitas, Obat → preview Tujuan/Catatan hari ini → Insight. Semua rata kiri. Kartu radius 24, interval bagian 24–32, kontrol tinggi minimal 48, judul 30 dan body 16 mengikuti tokens existing. Tanpa foto tambahan karena belum ada aset berlisensi terverifikasi. Jangan membuat angka atau grafik dummy.

Inspeksi arsip existing: format FigCraft v1, halaman 00 Cover & Brief, 01 Design System, 02 Screens, 03 States; imageIndex kosong. Thumbnail cover sudah diperiksa. Preview Flutter dengan font Inter dan ikon asli diperiksa pada viewport 390×844; pemeriksaan layout otomatis mencakup 320 px dan text scale 2. Tidak ada klaim parity dengan editable FigCraft baru.

Foundation: tiap domain diberi label “Belum tersedia”, nilai null dari API. Goals, timeline, dan insight berupa preview noninteraktif dengan penjelasan. Quick Record baru aktif ketika destination form slice berikutnya tersedia. Pertahankan navigasi Beranda/Profil sampai Log dan Insights memiliki layar fungsional; target akhir Today/Log/Insights/Profile.

States: loading indikator semantik; error dan koneksi gagal tanpa menampilkan data lama, tombol Coba lagi; consent-required dengan aksi pengelolaan consent; success menampilkan metadata akun aktual dan preview domain. Refresh mengambil respons baru. Tidak mengklaim dukungan offline atau sync pending. Responsive: satu kolom pada 320–600 px dan text scale 1–2; tanpa fixed-height konten. Screen reader: heading, tombol avatar bernama, preview tidak diberi button semantics.

Organisasi handoff berikutnya: 09 Today, 10 Nutrition, 11 Glucose, 12 Activity, 13 Medication, 14 Goals, 15 Timeline, 16 Insights, 17 Offline/System, 18 Responsive, 19 Handoff. Bagian 10–19 masih rencana; design source editable dan parity FigCraft belum diverifikasi.
