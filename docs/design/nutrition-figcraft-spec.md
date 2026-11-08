# Nutrition — FigCraft dan screen/API contract

Desain native berhasil dibuat dan diverifikasi melalui FigCraft CLI 0.16.0 headless. Dokumen editable existing: `design/beOkay-ui.figcraft`; halaman `10 — Nutrition` (page 3932), enam frame tambahan. Halaman/desain lama dipertahankan. Desktop attach 7979 sempat berhasil handshake, tetapi document request timeout; tidak mengklaim GUI attach stabil. Headless adalah engine FigCraft asli, bukan gambar yang diklaim sebagai file editable.

Preview: `design/nutrition-overview.png` dan `design/nutrition-previews/`. Enam frame: Empty, Form, History, Detail, Correction, States. Render benar-benar dibuka dan diperiksa sebelum UI. Contoh histori berlabel ilustratif; tidak ada nilai gizi palsu. Belum ada varian responsive editable khusus atau approval desain pengguna. Frame bukan screenshot implementasi pixel-perfect; frontend memperluas state dan navigasi sesuai hasil pengujian.

Reuse Inter, enam brand colors existing, charcoal headline/hero, ice-blue contextual states, white surfaces, radius 24/input16/pill; layout vertikal scroll dan safe area. Flutter memakai theme/component existing. Tidak menambah foto tanpa aset berlisensi atau AI food-recognition palsu.

| Screen/action | State dan API |
|---|---|
| Today Nutrition card | GET Today → count/known energy/partial label; empty yang nyata; Catat/Histori links |
| Quick Record | Shared bottom sheet; Makanan membuka `/meals/new`; tiga domain lain disabled/belum tersedia |
| Meal form | Category chips, timestamp picker, notes, 1–30 items; POST meals dengan UUID stabil; loading, validation, server error; save/retry mempertahankan input |
| Catalog picker | Search ≥2 char → GET foods/search; empty/error/retry; create personal food via POST me/foods |
| Personal food form | Name/source, optional per-100g nutrient fields, estimate toggle; tidak prefill unknown dengan nol |
| Item editor | Free-text atau catalog snapshot, quantity/unit, optional total estimated grams; nutrition preview hanya jika input mendukung |
| History | GET meals keyset pagination, filter user-local date, active/archive, date grouping, detail link, kembali Today |
| Detail | GET meal; time in preference timezone, source labels, nutrient coverage; edit/archive/restore, Beranda action |
| Correction | GET latest then PATCH expectedVersion/reason; conflict requires reloading; no silent overwrite |
| Revisions | GET revisions; prior item names/quantities and timestamp expandable |
| Archive/restore | Confirmation dialog requires reason; PATCH archived plus expectedVersion |

Timestamp input memakai zona perangkat dengan label eksplisit; histori dan Today memakai zona preferensi dari API. Tidak menyamakan tanggal device dengan tanggal pengguna secara diam-diam. Full arbitrary-IANA picker di form masih perlu pengembangan bila produk menghendakinya.

Visual QA Appium memeriksa form, unknown detail, source-labelled catalog detail, history dan Today. Setelah observasi, akses kembali dari root detail/history diperbaiki dan label unit/source dibuat ramah pengguna. Responsive coverage Nutrition masih terbatas pada widget/ukuran yang tercatat dalam laporan pengujian; jangan mengklaim semua ukuran/perangkat terverifikasi.
