# Rancangan pilot kegunaan beOkay — draf

> Status: **DRAF, belum disetujui komite etik.** Tidak ada perekrutan, pengumpulan data, atau klaim hasil sebelum persetujuan etik dan tinjauan klinisi keselamatan selesai. Disusun 11 November 2026 (beOkay 3.0 Fase 7, kapabilitas P3-13).

## 1. Tujuan dan batas klaim

Pilot ini mengukur **kegunaan dan beban pencatatan**, bukan dampak klinis. Pilot singkat tanpa kelompok pembanding tidak dapat membuktikan perubahan HbA1c, berat badan, atau pencegahan komplikasi, sehingga hasilnya tidak boleh dipakai sebagai klaim kesehatan.

Pertanyaan yang dijawab:

1. Bisakah orang dewasa dengan diabetes tipe 2 mencatat makan, glukosa, aktivitas, dan obat tanpa bantuan?
2. Berapa lama dan seberapa sering mereka mencatat selama empat minggu, dan kapan berhenti?
3. Apa yang membingungkan, membebani, atau terasa tidak aman?

## 2. Rancangan

| Unsur | Usulan |
|---|---|
| Desain | satu kelompok, 4 minggu, ditambah sesi kegunaan termoderasi di awal dan akhir |
| Peserta | 10–15 orang dewasa (≥ 18 tahun) dengan diagnosis T2DM dari tenaga kesehatan, memakai Android sendiri |
| Eksklusi | hamil; diabetes tipe 1; riwayat hipoglikemia berat dalam 3 bulan; tidak bisa membaca bahasa Indonesia |
| Rekrutmen | lewat fasilitas atau komunitas yang ditentukan bersama komite etik; bukan lewat aplikasi |
| Persetujuan | lembar persetujuan riset terpisah dari consent di aplikasi; peserta boleh berhenti kapan saja tanpa akibat |
| Insentif | ditentukan bersama komite etik; tidak bergantung pada seberapa sering mencatat |

## 3. Ukuran

Semua ukuran dapat diperoleh tanpa menambah pelacakan baru di aplikasi.

| Ukuran | Cara | Sumber |
|---|---|---|
| Penyelesaian tugas | 6 tugas termoderasi (daftar dan verifikasi email, catat makan dari kalimat, catat glukosa, konfirmasi obat, buka Wawasan, ekspor data); berhasil / dengan bantuan / gagal, waktu per tugas | pengamat |
| Kegunaan | System Usability Scale (10 butir) di minggu 0 dan 4 | kuesioner di luar aplikasi |
| Beban | 3 pertanyaan terbuka + skala 1–5 "seberapa merepotkan mencatat" di minggu 2 dan 4 | wawancara singkat |
| Frekuensi dan retensi pencatatan | hari dengan ≥ 1 catatan per minggu; minggu terakhir aktif | **ekspor data milik peserta** (`beokay-export-v2`) yang diserahkan peserta secara sukarela di akhir pilot |
| Keselamatan | kartu keselamatan yang muncul (kode, tanpa isi pesan); kejadian tidak diinginkan yang dilaporkan peserta | ekspor peserta (`agent_run_events` tipe `SAFETY_SCREEN`) dan laporan langsung |

Data kesehatan peserta tidak diambil langsung dari basis data produksi. Peserta mengunduh ekspornya sendiri dari Pengaturan → Privasi & data; tim riset hanya menerima berkas yang diserahkan, lalu menyimpannya terpisah dari identitas peserta.

## 4. Pemantauan keselamatan

- Setiap kartu keselamatan "Segera cari bantuan" atau laporan gejala dari peserta ditindaklanjuti tenaga kesehatan pendamping dalam 1 hari kerja.
- Kejadian tidak diinginkan serius dilaporkan ke komite etik sesuai ketentuannya.
- Pilot dihentikan bila ada kejadian serius yang terkait dengan saran aplikasi.

## 5. Gerbang sebelum pilot

| Gerbang | Status 11 Nov 2026 | Bukti / pemilik |
|---|---|---|
| Persetujuan komite etik | belum dimulai | pemilik |
| Tinjauan klinisi `safety-policy-v2` | menunggu | [safety-clinical-review-packet.md](safety-clinical-review-packet.md) |
| Tinjauan hukum teks consent dan kebijakan privasi | masih draf | pemilik |
| Kunci rilis Android dan pendaftaran Firebase `id.beokay.app` | belum (milik pemilik) | runbook §6 butir 3–4 |
| Deploy produksi + cadangan terjadwal | skrip siap, belum dijadwalkan | `scripts/ops/db-backup.sh`, runbook §5 |
| CI hijau di GitHub | workflow siap, belum pernah berjalan (belum di-push) | `.github/workflows/ci.yml` |
| Kontak dukungan dan prosedur insiden untuk peserta | belum | pemilik |
| Kebijakan retensi data pilot | belum | pemilik + komite etik |

## 6. Analisis

Deskriptif saja: proporsi tugas berhasil, median waktu per tugas, skor SUS (median, rentang), hari pencatatan per minggu per peserta, minggu terakhir aktif, dan tema dari wawancara. Tidak ada uji hipotesis dan tidak ada klaim sebab-akibat.
