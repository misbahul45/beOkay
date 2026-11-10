# P3 — rencana eksekusi dan status (10 November 2026)

P3 yang diminta sangat luas (13 kapabilitas); teks promptnya juga terpotong di tengah §9. Yang dikerjakan di sesi ini adalah **irisan vertikal yang bisa diverifikasi**, bukan seluruh P3.

| ID | Kapabilitas | Status | Yang ada / tidak ada |
|---|---|---|---|
| P3-01 | Audit kesiapan P2 | **DONE** | `docs/audits/p3-readiness-audit.md` |
| P3-02 | Mesin intervensi JITAI | **IMPLEMENTED_AND_TESTED (tahap awal)** | Kebijakan murni `jitai-policy-v1`; pemicu: permintaan sendiri, jendela tujuan, rutinitas pilihan, ulasan mingguan; keputusan "tidak" dicatat dengan alasan; jam tenang, jatah harian/mingguan, jeda minimum, jeda dan mati-kan-jenis oleh pengguna, tanpa eskalasi karena diam, duplikat/zona waktu. Tidak ada: pemicu otomatis dari jadwal server, kanal notifikasi lokal/push dari keputusan |
| P3-03 | Pengiriman dan pelacakan tanggapan | **PARTIAL** | Kanal IN_APP saja; siklus ELIGIBLE→DELIVERED→OPENED/SNOOZED/RESPONDED/EXPIRED/CANCELLED; tanggapan USEFUL, NOT_USEFUL, NOT_NOW, TOO_FREQUENT, ALREADY_DONE, DISMISSED, STOP_THIS_TYPE (masing-masing berakibat nyata); peristiwa outbox. Tidak ada: LOCAL_NOTIFICATION/push dari keputusan, "ubah jadwal" |
| P3-04 | Intelijen longitudinal | **NOT_STARTED** | Tidak ada baseline pribadi, tren, atau propagasi koreksi. Ringkasan/tren P1 ada tetapi bukan sistem baseline P3 |
| P3-05 | Tata kelola personalisasi lanjutan | **PARTIAL** | Level 1–2 (preferensi eksplisit; adaptasi umpan balik deterministik `pref-rules-v2`) dan model terdaftar berstatus. Tidak ada registri kebijakan, evaluasi offline, atau bandit |
| P3-06 | Eksperimen dan efektivitas | **NOT_STARTED** | Tidak ada penugasan, pelacakan paparan, atau analisis. Sengaja tidak dibuat tanpa persetujuan riset |
| P3-07 | MLOps dan evaluasi agen | **PARTIAL** | Registri model, persetujuan berlog, audit inferensi, fallback. Tidak ada pemantauan drift, rollback otomatis, evaluasi trajektori |
| P3-08 | Tata kelola keselamatan klinis | **NOT_STARTED** | Kebijakan regex tetap, belum ditinjau klinisi; tidak ada siklus hidup kebijakan |
| P3-09 | Keamanan komunitas | **PARTIAL** | Alias tervalidasi, opt-in, kohort ≥ 5. Tidak ada moderasi, deteksi penyalahgunaan |
| P3-10 | Operasi privasi dan keamanan | **PARTIAL** | Consent per tujuan, ekspor data, hapus akun (cascade). Tidak ada kebijakan retensi terjadwal, uji penetrasi |
| P3-11 | Keandalan dan rilis | **NOT_STARTED** | Tidak ada SLO, pemantauan, pemulihan bencana, feature flag |
| P3-12 | Kematangan UX Flutter | **PARTIAL (dikerjakan sesuai permintaan)** | Pembersihan info berlebih di seluruh aplikasi, bahasa non-teknis, kartu saran + kontrol, gizi dari RAG pada foto. Belum: pengaturan personalisasi lengkap, audit aksesibilitas formal |
| P3-13 | Evaluasi pilot | **NOT_STARTED** | Tidak ada protokol, perekrutan, atau laporan bukti. Tidak boleh diklaim tanpa persetujuan etik |

## Prinsip yang dijaga
`NO_INTERVENTION` adalah hasil umum; LLM/ML tidak menimpa kebijakan deterministik; tidak ada klaim klinis; tidak ada pemicu yang menafsirkan data yang hilang sebagai izin untuk mendesak pengguna.
