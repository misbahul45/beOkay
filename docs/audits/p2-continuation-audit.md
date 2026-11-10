# P2 — audit lanjutan dan matriks celah (9 Nov 2026)

## Keputusan arsitektur yang berlaku (menimpa prompt lanjutan)
Prompt lanjutan menyebut Python/FastAPI/LangGraph. Pemilik produk sebelumnya memutuskan **tanpa service Python/AI/ML di compose**: runtime agen ada di Bun/TypeScript (graf status eksplisit yang disimpan di PostgreSQL), LLM = Mistral lewat HTTP, ML = dilatih di Kaggle lalu dideploy ke Modal dan dipanggil lewat HTTP. Keputusan itu dipertahankan; tidak ada `ai/` Python. Akibatnya "LangGraph checkpointer" digantikan oleh tabel `agent_runs` + `agent_run_events` (state machine berbasis DB), dengan sifat yang sama yang dibutuhkan: id run stabil, isolasi akun, kuitansi idempotensi, dan pemulihan setelah restart.

## Keadaan sebelum sesi ini
Dari pemeriksaan kode: tidak ada runtime agen, rekomendasi, personalisasi, komunitas, tantangan, papan peringkat, maupun model ML. `server/src/agentic` dan `server/src/modules` hanya direktori kosong. Yang ada dari P1 dan dipakai ulang: referensi TKPI (pgvector, 1.037 baris verified_auto), preferensi/alergi, pencarian pangan, pengingat, consent.

## Matriks celah (diperbarui setelah implementasi, 9 Nov 2026)

| ID | Kapabilitas | Status | Bukti | Sisa |
|---|---|---|---|---|
| C01 | Eksekusi tahan restart | **IMPLEMENTED_AND_VERIFIED** (nutrisi + aktivitas, multi-giliran, SSE) | `agent*.test.ts`, `p2-closed-loop.test.ts`; restart proses API sungguhan (E2E-05); pemulihan setelah restart aplikasi di emulator | Tes otomatis restart proses nyata belum ada (hanya pembuktian skrip) |
| C02 | Alat nyata | **PARTIAL** | LLM hanya menulis teks (bukan alat); 6 alat berkontrak (preferensi, personalisasi, TKPI, katalog pengguna, konteks aktivitas, tujuan perilaku) | Alat glukosa/ringkasan, kalkulator, korpus bukti terkurasi belum |
| C03 | Modal ML | **IMPLEMENTED_AND_VERIFIED (RESEARCH_ONLY, bayangan)** | Kaggle: akurasi tanpa duplikat 0,955; Modal live, uji auth/skema/latensi; registri + audit; emulator | Status tetap RESEARCH_ONLY (lisensi dataset, bukan foto nyata); registrasi produksi |
| C04 | Keselamatan & bukti | **IMPLEMENTED_AND_TESTED** | `agent-safety.test.ts`, `agent*.test.ts` | Korpus bukti non-gizi; tinjauan klinisi |
| C05 | Nutrisi personal | **IMPLEMENTED_AND_TESTED** (backend + UI + emulator) | `agent.test.ts`, `coach_test.dart` | Modifikasi saran, anggaran/waktu masak |
| C06 | Aktivitas adaptif | **IMPLEMENTED_AND_TESTED** (backend + UI + emulator) | `activity-graph.test.ts`, `agent-activity.test.ts`, emulator | Personalisasi aktivitas, outcome terukur |
| C07 | Lingkar umpan balik | **IMPLEMENTED_AND_TESTED** | Penolakan → penalti; hasil terukur dari catatan makan/aktivitas → bonus (`pref-rules-v2`), penarikan saat bukti diarsipkan | Preferensi waktu; personalisasi aktivitas; pencocokan nama heuristik |
| C08 | Komunitas | **IMPLEMENTED_AND_TESTED** | `community.test.ts`, `community_test.dart`, emulator | Moderasi konten (tidak ada konten bebas sengaja) |
| C09 | Tantangan & papan peringkat | **IMPLEMENTED_AND_TESTED** | `scoring.test.ts`, `community.test.ts`, emulator | Kohort ≥ 5 hanya diuji dengan data tes, bukan di perangkat |
| C10 | Flutter | **IMPLEMENTED (tes widget + emulator)** | `coach_test.dart`, `community_test.dart` | Tanpa desain FigCraft |
| C11 | Event/outbox | **IMPLEMENTED_AND_TESTED** | `outbox_events` transaksional, SKIP LOCKED, backoff, dead-letter, dedupe | Hanya konsumen internal |
| C12 | Observabilitas & biaya | **PARTIAL** | `agent_tool_calls`, `ml_inference_runs`, peristiwa `LLM_TEXT` (model, latensi, fallback), `outbox` stats, batas laju | Metrik agregat, korelasi trace ke Flutter, biaya token |

## Cacat dan temuan nyata dari sesi ini
- **Tinggi (diperbaiki):** `consent_records` punya CHECK di DB yang hanya mengenal tiga tujuan. Menambah tujuan baru di kode menghasilkan 500 saat pemberian. Diperbaiki dengan migrasi `20261109100100_consent_personalized_ai`.
- **Sedang (diperbaiki sebelum rilis):** penalti peringkat awal 0,15 tidak mengubah urutan setelah satu penolakan (skor dasar 1/(peringkat+1)). Dinaikkan ke 0,6 dan diuji: butir yang ditolak tidak lagi di puncak.
- **Catatan desain:** tujuan consent `personalized_ai` ditambahkan **tanpa menaikkan versi kebijakan** agar persetujuan yang ada tidak batal massal. Perlu ditinjau pemilik produk/hukum.
