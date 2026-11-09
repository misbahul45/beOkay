# P2 — rencana eksekusi (revisi 9 November 2026, setelah arahan pengguna)

Pola kerja: **satu tahap besar → berhenti → pengguna commit** (agen tidak menjalankan `git add/commit/push`). Perintah build/tes di Docker; Flutter di host. Dokumen berada di `docs/…`.

## Keputusan pengguna yang mengubah rencana awal

| Arahan | Dampak |
|---|---|
| **Tanpa service Python/AI/ML di compose** | Runtime agen ditulis di **Bun/TypeScript** di dalam API yang ada (fitur `features/agent/*`). LLM dipanggil lewat HTTP (`LLM_BASE_URL`, kompatibel OpenAI). Tidak ada kontainer baru. |
| **Model dibangun lewat Kaggle, dideploy ke Modal, API memanggil lewat HTTP** | Pelatihan memakai Kaggle (kernel, GPU gratis Kaggle) dan dataset publik Kaggle. Artefak diunggah ke Volume Modal, disajikan oleh endpoint web Modal; Bun hanya `fetch` + validasi respons. Satu-satunya kode Python adalah berkas deploy Modal (`ml/modal_app.py`) dan notebook latih — **artefak deploy, bukan service di repo/compose**. |
| **Deploy lewat Modal MCP** | `modal-mcp-server` memakai CLI `modal`; saat ini **token Modal belum ada** (`Token missing`) → deploy terblokir sampai pengguna menjalankan `modal token new`. |
| **TKPI PDF dijadikan RAG makanan/nutrisi** | Ingest dengan OCR + validator deterministik (lihat bawah). Berkas: `/home/misbahul45/Downloads/Tabel Komposisi Pangan Indonesia.pdf` (6,3 MB, 140 hlm). |
| **UploadThing** | Penyimpanan berkas (dev). `UPLOADTHING_TOKEN` disimpan di `.env` (gitignored), nama saja di `.env.example`. Akun demo, akan dihapus pengguna. |

LangGraph (Python) dari prompt induk **tidak dipakai**. Sebagai gantinya: graf status eksplisit di TypeScript (node, transisi tervalidasi, checkpoint di Postgres lewat Prisma, interupsi untuk konfirmasi). Alasannya: tidak ada runtime Python; checkpoint di tabel sendiri memudahkan hapus-akun/tarik-consent; tanpa dependensi besar baru.

## Koreksi temuan sebelumnya (TKPI)

Audit P1 menyatakan PDF "tidak terbaca andal". Setelah uji OCR Mistral pada halaman sampel, tabel terbaca rapi dan angkanya konsisten secara internal (contoh: Dodol Banjarmasin 2,6×4 + 8,6×9 + 70×4 = 367,8 ≈ 368 kkal tercatat). Kesimpulan lama terlalu pesimis untuk halaman itu. Aturan tetap: **baris hanya masuk sebagai `reference_verified`-otomatis bila lolos validator** (energi ≈ Atwater ±10%, air+protein+lemak+KH+abu ≈ 100 g ±5%, nilai dalam rentang masuk akal). Baris gagal → `needs_review`, **tidak** dipakai kalkulator maupun agen. Tingkat lolos dilaporkan per bab.

**Hasil ingest nyata (OCR Mistral `mistral-ocr-latest`, 140 hlm → `server/src/features/food-reference/tkpi-parser.ts`):** 1.132 baris pangan di bab 4 → **1.037 lolos (91,6%)**, 95 `needs_review`. Alasan penolakan: ATWATER_MISMATCH 69, PROXIMATE_SUM_OFF 37, MISSING_MACRO 2, OUT_OF_RANGE_ASH 1 (sebuah baris bisa kena lebih dari satu). Per bab terendah: 4.11 Gula/Konfeksioneri 10/18, 4.3 Kacang 123/138. 174 baris punya 24 kolom (sel kosong hilang); makronya tetap divalidasi. Catatan jujur: "lolos" berarti **konsisten secara internal**, bukan diperiksa manusia; kesalahan OCR yang kebetulan menjaga Atwater tidak akan tertangkap. Karena itu status disimpan sebagai `verified_auto`, bukan `reference_verified`, dan pengguna melihat sumber "TKPI (OCR, pemeriksaan otomatis)". Hanya makro (air, energi, protein, lemak, KH, serat, abu) yang diambil; mikro tidak diingest.

## Tahap

| Tahap | Isi | Bukti selesai | Status |
|---|---|---|---|
| **A — P2-00** | Audit, peta dependensi | 3 dokumen; baseline 69 + 97 tes | selesai |
| **B — RAG pangan (TKPI)** | OCR 140 hlm → parser deterministik → validator → tabel `food_reference` (+ `pgvector`, embedding `mistral-embed`) → pencarian hibrida (nama + vektor) → masuk Food Discovery sebagai sumber lokal terverifikasi; unggah PDF sumber ke UploadThing | tes unit parser/validator; tes integrasi pencarian; laporan tingkat lolos | OCR berjalan |
| **C — Fondasi agen** | Migrasi (conversations, runs, run_events, tool_calls, checkpoints, consent purposes v1.1); gateway `/api/me/agent/*` + SSE + cancel; mesin status run; API konteks bercakupan; registri alat deny-by-default; keselamatan deterministik berversi | tes Bun lulus di Docker; tes adversarial (injeksi, akun lain, dosis obat) | belum |
| **D — Graf agen & bukti** | Graf TS (intent → konteks → klarifikasi → alat → keselamatan → konfirmasi → simpan), klien LLM HTTP, retrieval bukti dari korpus yang ditinjau | tes graf, resume tanpa efek ganda | belum |
| **E — Model Kaggle → Modal** | Pilih model & dataset, latih di kernel Kaggle, evaluasi (split bersih, tanpa kebocoran), registri model, `ml/modal_app.py`, klien HTTP + circuit breaker + fallback | laporan evaluasi nyata; **deploy hanya bila token Modal ada** | terblokir token |
| **F — Nutrisi & aktivitas** | Preferensi/alergi, rencana makan (≠ konsumsi), filter kendala keras, peringkat, opsi aktivitas manual | tes alergi, tidak ada auto-log | belum |
| **G — Coaching & komunitas** | Mikro-aksi, tinjauan mingguan; wilayah, alias, keanggotaan, tantangan, buku besar skor, leaderboard, blok/laporan | tes isolasi, skor idempoten | belum |
| **H — Flutter** | Desain FigCraft dulu, lalu layar | **terblokir sampai figcraft tersambung** | belum |
| **I — Verifikasi** | Suite penuh, regresi, laporan akhir dengan status jujur | — | belum |

## Pemilihan model (dibuat jujur, bukan semua model)

Dari kandidat prompt induk, hanya yang punya dataset publik nyata dan tugas jelas yang layak: **pengenal makanan Indonesia dari foto** (dataset gambar di Kaggle, mis. `robertusbagaskara/indonesian-food-image`, `faldoae/padangfood`, `rizkyyk/dataset-food-classification`) untuk memperbaiki daftar nama kandidat pada Food Vision (tetap tanpa kalori/porsi). Model *ranker* makanan/aktivitas dan *habit adherence* **tidak** dilatih: tidak ada data interaksi pengguna nyata, dan data sintetis bukan bukti akurasi. Peringkat memakai aturan deterministik. Status model: `RESEARCH_ONLY` sampai evaluasi dan peninjauan; hanya `APPROVED` yang boleh memengaruhi pengguna.

## Yang dibutuhkan dari pengguna

1. **Modal**: jalankan `! modal token new` (login browser) — atau beri `MODAL_TOKEN_ID`/`MODAL_TOKEN_SECRET`. Tanpa ini deploy tidak dapat dilakukan dan tidak akan saya klaim.
2. **FigCraft**: sambungkan ulang sebelum tahap H.
3. Kebijakan kohort minimum komunitas dan teks consent baru perlu ditinjau pemilik produk.
