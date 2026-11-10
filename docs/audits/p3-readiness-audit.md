# P3 — audit kesiapan (10 November 2026)

Klasifikasi memakai kata yang jujur. "Kode ada" bukan bukti keandalan operasional.
Catatan arsitektur: prompt P3 menyebut Python/FastAPI/LangGraph. Keputusan pemilik sebelumnya (tanpa layanan Python/AI/ML di compose; runtime agen di Bun/TypeScript dengan state di PostgreSQL) **tetap berlaku** dan tidak diubah.

## Gerbang kesiapan P2 (§3.4)
| # | Kemampuan | Klasifikasi | Bukti |
|---|---|---|---|
| 1 | Permintaan AI terautentikasi | VERIFIED_IN_INTEGRATION_TESTS + emulator | `agent.test.ts`, emulator Pixel_4 |
| 2 | Pemeriksaan consent | VERIFIED_IN_INTEGRATION_TESTS + emulator | tolak tanpa izin, aktif setelah diberikan |
| 3 | Konteks hanya milik pengguna | VERIFIED_IN_INTEGRATION_TESTS | isolasi akun, `userId` tidak dari argumen |
| 4 | Eksekusi alat (graf status di Postgres, bukan LangGraph) | VERIFIED_IN_INTEGRATION_TESTS | `agent*.test.ts`, SSE, restart proses API nyata |
| 5 | Saran aman | VERIFIED_IN_INTEGRATION_TESTS | `safety-policy-v1`, gerbang teks LLM |
| 6 | Konfirmasi pengguna | VERIFIED_IN_INTEGRATION_TESTS + emulator | |
| 7 | Mutasi domain idempoten | VERIFIED_IN_INTEGRATION_TESTS | kuitansi `(user_id, operation_id)`; restart nyata |
| 8 | Umpan balik | VERIFIED_IN_INTEGRATION_TESTS | |
| 9 | Riwayat saran | PARTIALLY_IMPLEMENTED | rencana makan/aktivitas ada; tidak ada layar riwayat saran lintas-hari |
| 10 | Inferensi model atau fallback deterministik | VERIFIED_PRODUCTION_LIKE (dev) | Modal live, fallback bila gagal/lambat, audit LIVE/SHADOW |
| 11 | Privasi komunitas | VERIFIED_IN_INTEGRATION_TESTS + emulator | alias saja, kohort ≥ 5, skema tanpa FK ke data kesehatan |
| 12 | Koreksi skor tantangan | VERIFIED_IN_INTEGRATION_TESTS | ledger append-only, pembalikan saat arsip |

Cacat P2 yang ditemukan dan sudah ditutup sebelum P3: pemulihan layar Asisten setelah restart, cold start Modal, timeout fetch tiruan, gerbang kecocokan referensi gizi (lihat laporan).

## Celah terbuka yang relevan bagi P3
| ID | Celah | Status | Risiko |
|---|---|---|---|
| G-01 | Tes acak gagal pada jam 23:00–23:59 UTC (identity 429 saat suite diulang < 60 dtk; trends/push-dispatcher sekali-sekali) | DEFECT_CONFIRMED (akar: sebagian terbukti — batas laju sign-up 5/menit; sebagian dugaan — sensitif tanggal UTC) | tes tidak dapat dipercaya penuh di jam itu |
| G-02 | Drift Prisma: 3 objek khusus-SQL (2 FK, 1 indeks unik) | VERIFIED (tidak berbahaya) | rendah |
| G-03 | Push FCM nyata terblokir (Firebase belum didaftarkan) | BLOCKED | pengiriman di luar aplikasi belum teruji |
| G-04 | Model foto hanya `APPROVED` di DB dev | IMPLEMENTED_NOT_VERIFIED di produksi | lihat laporan P2 |
| G-05 | RAG gizi hanya TKPI (1037 baris lolos; contoh: tidak ada "nasi goreng", "lontong", "sambal") | PARTIALLY_IMPLEMENTED | cakupan makanan olahan rendah |
| G-06 | Tanpa observabilitas agregat, tanpa SLO, tanpa pemulihan bencana | MISSING | tinggi untuk pengguna nyata |
