# P0 UI — riset dan keputusan

8 November 2026. Cakupan: navigasi 4 tab, Today, Catatan (Log), Wawasan (Insights), Quick Record. Bukan audit visual seluruh aplikasi.

## Status desain FigCraft

MCP `figcraft` gagal terhubung pada sesi ini (`CONNECTION_CLOSED`), sehingga perubahan di bawah **belum dirancang ulang di FigCraft**. Acuan yang dipakai: frame wireframe P0 yang sudah ada di `design/beOkay-ui.figcraft` (halaman 13–19, `design/*-p0-overview.png`) dan `docs/design/p0-completion-spec.md`, ditambah token yang ada (`design/beokay_tokens.dart`). Tidak ada mockup pengganti. File FigCraft perlu diperbarui setelah koneksi MCP pulih.

## Temuan riset dan penerapannya

Tingkat bukti dicantumkan agar tidak tertukar dengan opini desain.

| Topik | Temuan | Sumber | Penerapan |
|---|---|---|---|
| Jumlah tujuan nav bawah | Navigation bar untuk 3–5 tujuan pada level hierarki yang sama | [Android Developers – navigation bar](https://developer.android.com/develop/ui/compose/components/navigation-bar) | 4 tab: Beranda, Catatan, Wawasan, Profil. Tanpa tab Komunitas/AI (di luar P0) |
| Label nav | Label opsional di M3 (SAP Fiori M3 usage); halaman m3.material.io tidak berhasil diambil | [SAP M3 navigation bar](https://www.sap.com/design-system/fiori-design-android/v26-1/components/m3-standard-components/navigation-bar/usage) | **Keputusan sendiri**: label selalu tampil (ikon + teks) karena pengguna kesehatan beragam literasi digital |
| Ukuran target sentuh | Material 48dp; WCAG 2.2 SC 2.5.8 minimum 24×24 CSS px (AA); 44–48 adalah rekomendasi, bukan syarat | [W3C Understanding 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html), [Google accessibility](https://support.google.com/accessibility/android/answer/7101858?hl=en-GB) | Semua tombol/chip/tile ≥ 48dp (tile 72dp) |
| Skala teks | Flutter membaca skala font OS; tata letak harus punya ruang; hindari tinggi tetap pada wadah teks. Android 14 skala nonlinear sampai 200%. Angka uji 200% adalah konvensi, bukan aturan Flutter resmi | [Flutter – UI design & styling](https://docs.flutter.dev/ui/accessibility/ui-design-and-styling), [Android 14 nonlinear scaling](https://docs.flutter.dev/release/breaking-changes/android-14-nonlinear-text-scaling-migration) | Diuji di HP pada font scale 2.0 (lihat verifikasi). Label nav dibatasi 1.3× seperti NavigationBar Material |
| Empty state | Jelaskan mengapa kosong dan beri satu langkah berikutnya; bedakan kosong pertama kali, hasil filter, dan terhapus | [Carbon empty states](https://carbondesignsystem.com/patterns/empty-states-pattern/), [Salesforce Lightning](https://v1.lightningdesignsystem.com/guidelines/empty-state), [PatternFly](https://v4-archive.patternfly.org/v4/design-guidelines/usage-and-behavior/empty-state) | Komponen `EmptyState`; Log punya tiga varian (kosong, terfilter, arsip kosong); nilai kosong tidak pernah ditampilkan sebagai angka |
| Data glukosa jarang/hilang | Celah sensor tampil sebagai celah, bukan interpolasi; tampilkan usia data; label angka untuk pembeda selain warna. Sumber: blog vendor dan paten, **bukan standar** | [vp0.com CGM chart UI](https://vp0.com/blogs/cgm-glucose-chart-ui-swiftui), paten US 10867420 | Tidak ada grafik garis; hanya angka dan statistik deskriptif. Setiap kartu memuat "dihitung … · terkini/mungkin berubah · jam" |
| Usability aplikasi diabetes | Studi kecil: pelanggaran heuristik Nielsen, perlu bantuan/tutorial, operasi rawan salah, grafik tidak jelas; belum ada daftar periksa tervalidasi khusus pencatatan glukosa | [Heuristic evaluation (Thieme)](https://www.thieme-connect.de/products/ejournals/pdf/10.1055/s-0038-1660438.pdf), [JMIR 2026](https://www.jmir.org/2026/1/e86024/XML) | Bukti lemah; dipakai hanya sebagai arah: sedikit langkah ke pencatatan (Quick Record satu ketukan di Beranda dan Catatan), teks status eksplisit |
| DB lokal terenkripsi (offline) | Drift + SQLite3MultipleCiphers (drift ≥ 2.32) atau `encrypted_drift`; hindari konflik `sqlite3_flutter_libs`; ID dibuat klien agar sinkron menjadi upsert | [Drift encryption docs](https://drift.simonbinder.eu/docs/platforms/encryption/) | **Belum diterapkan** (slice offline belum dikerjakan). Paket `sync_queue_drift` / `offline_sync_data` masih 0.1.x, perlu evaluasi |

## Keputusan desain yang berasal dari audit di HP

Audit Beranda lama di Redmi (2409BRN2CY, 720×1640, Android 15):

1. Hanya 2 tab; kartu Obat/Tujuan/Insight berupa placeholder "belum tersedia".
2. Kartu hero "Setiap catatan membantu." menghabiskan ±400px tanpa fungsi, dan Quick Record ganda.
3. Aksi kartu ("Catat glukosa", "Riwayat glukosa") berupa teks tanpa bentuk tombol.
4. Keadaan kosong memakai gaya headline ("Durasi belum tersedia.") sehingga terbaca seperti data.
5. Greeting, tanggal, dan zona waktu tersebar di tiga baris terpisah.

Perubahan: nav 4 tab; hero dihapus; `MetricCard` (ikon, judul, nilai hanya bila ada data, keterangan, tombol 48dp + tautan Riwayat); `TimelineTile` dipakai bersama di Beranda dan Catatan; satu kartu "Sedang disiapkan" menggantikan tiga placeholder; tarik-untuk-muat-ulang menggantikan tombol "Muat ulang ringkasan"; AppBar kosong dihapus pada tab tanpa judul.

Cacat yang hanya terlihat di perangkat (skala teks 2.0), diperbaiki: judul "Catatan" patah menjadi "Catat/an", label nav terpotong ("Bera…"), badge membuat judul "Glukosa" patah per huruf.

## Belum dilakukan

Obat, Tujuan, Ringkasan Mingguan lintas domain, filter Obat/Tujuan di Catatan, offline/sinkronisasi, pembaruan FigCraft, pengujian VoiceOver/TalkBack, dan pengujian pada perangkat lain.
