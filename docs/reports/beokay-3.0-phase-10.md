# beOkay 3.0 — Fase 10: Hibrida agentik v2

> Tanggal: 12 November 2026. Cakupan dari [gap analysis §8](../audits/gap-analysis-2026-11-12.md): A-2 → A-7, A-1, A-6, A-4, A-5, A-9, A-8.
> Desain FigCraft: halaman "31 — Fase 10: Hibrida agentik v2" di `design/beOkay-ui-v3.figcraft`, ekspor `design/exports/31-*.png`, dibuat **sebelum** UI fase ini ditulis.

## 1. Ringkasan

| Butir | Hasil | Status |
|---|---|---|
| A-2 harness evaluasi | korpus 154 pesan beranotasi + 20 pesan terpisah; uji regresi router; `scripts/eval/router-eval.ts` untuk model sungguhan | **selesai** |
| A-7 threat model | [agent-threat-model.md](../security/agent-threat-model.md) per alat, OWASP LLM 2025; 20+ uji injeksi parser | **selesai** |
| A-1 pengklasifikasi terkendali | model mengusulkan rute untuk pesan `UNKNOWN`; aturan memvalidasi; tiap usulan dicatat | **selesai** |
| A-6 judge | lapis kedua yang hanya bisa menahan; korpus 100 kalimat injeksi | **selesai** |
| A-4 memori | konteks makan, hambatan, kondisi sementara; selalu diusulkan dulu; kedaluwarsa per jenis | **selesai** |
| A-5 memori episodik | ringkasan mingguan dari keputusan rencana; waktu yang sering ditolak tidak ditawarkan | **selesai** |
| A-9 "mengapa" | penjelasan rencana aktivitas dari statistik pengguna | **selesai** |
| A-8 model hidangan | `dish-classifier` → `DEPRECATED`; registrasi baru ditolak tanpa izin eksplisit | **selesai** |

Kriteria terima: (1) `UNKNOWN` turun ≥ 50% pada korpus tanpa satu pun pelanggaran gerbang: **terpenuhi** dengan `mistral-small-latest` (lihat §3); (2) semua usulan LLM tercatat dan tervalidasi aturan: **terpenuhi** (`router_proposals`, diuji); (3) threat model + 20 uji injeksi: **terpenuhi**.

## 2. Arsitektur

Urutan untuk setiap pesan Asisten:

1. Saringan keselamatan regex `safety-policy-v2` (tidak berubah). Diblokir → kartu keselamatan; model tidak pernah dipanggil.
2. Router aturan `router-v4` (logika v3). Rute dikenali → jalur deterministik.
3. Hanya bila `UNKNOWN`, bukan nama makanan, consent `ai_message_understanding` aktif, dan sakelar `llm_router` hidup: pola injeksi deterministik → bila lolos, pengklasifikasi dan judge dipanggil paralel (batas 6 dtk, `max_tokens` 160, keluaran JSON).
4. Judge `HOLD` → kartu keselamatan atau "belum paham". Judge `SAFE` tidak melonggarkan apa pun.
5. Usulan pengklasifikasi divalidasi: skema ketat, rute tertutup, keyakinan ≥ 0,6, kueri makanan harus kata dari pesan, menit harus tertulis, memori harus berdasar teks dan bebas kata sensitif.
6. Rute yang lolos dijalankan oleh `dispatch` yang sama dengan rute aturan. Balasan diberi penanda "Dipahami dengan bantuan model bahasa · aturan keselamatan tetap berlaku".

Model tidak pernah memilih alat, menulis catatan, atau menyimpan memori tanpa ketukan pengguna.

## 3. Hasil evaluasi dengan model sungguhan

`docker compose run --rm --no-deps api bun run scripts/eval/router-eval.ts`, model `mistral-small-latest`, 12 Nov 2026. Hanya kalimat korpus sintetis yang dikirim.

| Ukuran | Korpus (parafrase yang jatuh ke UNKNOWN) | Set terpisah |
|---|---|---|
| UNKNOWN pada router aturan | 39 | 9 |
| UNKNOWN setelah hibrida | 2 | 1 |
| Penurunan UNKNOWN | **94,9%** | **88,9%** |
| Rute benar | 34 | 6 |
| Rute salah | 3 | 2 |
| Galat model | 0 | 0 |

| Keamanan | Hasil |
|---|---|
| Kalimat injeksi | 100 |
| Pelanggaran gerbang | **0** |
| Injeksi yang sampai ke model | 0 (semua ditangkap saringan regex atau pola injeksi) |
| Latensi p50 / p95 | 765 / 1.425 ms |

Catatan kejujuran:

- Putaran pertama (prompt tanpa contoh) memberi 92,3% penurunan tetapi 8 rute salah, termasuk judge yang terlalu hati-hati. Prompt diperjelas dengan contoh yang **mirip kalimat korpus**, jadi angka korpus optimistis. Set terpisah 20 kalimat dibuat sesudahnya dan tidak dipakai untuk menyetel prompt.
- Hasil berubah sedikit antarputaran walau `temperature` 0 (34–36 benar pada korpus).
- Rute salah yang tersisa: permintaan perkembangan aktivitas dibaca komunitas, "mulai dari mana" dibaca bantuan, cara gabung grup dibaca bantuan, satu pertanyaan glukosa ditahan judge sebagai keselamatan, dan "tahu gejrot" menjadi kueri "gejrot" karena "tahu" ada di daftar kata henti router.
- Karena saringan injeksi menangkap seluruh korpus, efektivitas judge terhadap injeksi tidak terukur oleh korpus ini; uji unit dengan model jahat membuktikan validator menolak semua usulan berbahaya yang sampai ke model.

Uji otomatis tanpa jaringan memakai model palsu: orakel (validator tidak menolak usulan benar: UNKNOWN 39 → 0, 0 salah) dan model jahat (9 usulan jahat yang lolos pra-saring, 0 lolos validator).

## 4. Memori dan episode

- Pola deterministik: "yang masak di rumah biasanya istriku" → konteks makan; "sering lupa nyatet", "nggak ada waktu", "capek pulang kerja" → hambatan; "lagi puasa", "lagi flu", "lagi mudik" → kondisi sementara. Kalimat yang menyebut obat, diagnosis, atau penyakit berat tidak menghasilkan kondisi sementara.
- Model boleh mengusulkan memori hanya bila isinya berdasar teks; disimpan sebagai usulan dengan `sourceType = LANGUAGE_MODEL`, `confidence = INFERRED`.
- Kedaluwarsa: kondisi sementara 7 hari (puasa 14, Ramadan 30), hambatan 60 hari, konteks makan 180 hari; dihitung ulang saat dikonfirmasi; dibuang retensi 30 hari setelah lewat.
- "Sedang kurang sehat" membatasi rencana aktivitas Asisten ≤ 10 menit dan menahan usulan aktivitas rencana kecil.
- Episode mingguan (`episode-v1`) disusun dari rencana yang diterima/ditolak dan bukti per hari, tampil di refleksi sebagai "Yang kupelajari minggu lalu". Waktu yang ditolak ≥ 2 kali tidak dipakai sebagai waktu usulan berikutnya. Hambatan yang diingat dipilihkan lebih dulu di pertanyaan refleksi.

## 5. Pengujian

| Lapisan | Hasil |
|---|---|
| Backend `bun test` (stack uji bersih) | **376/376** (70 berkas); baru `router-corpus.test.ts` (3), `agent-hybrid.test.ts` (8), `tests/integration/phase10.test.ts` (6) |
| `tsc --noEmit` | bersih |
| Flutter | `flutter analyze` bersih; **227/227**; baru `phase10_test.dart` (3) |
| Evaluasi model sungguhan | §3 |

Temuan router aturan yang tercatat di korpus: "rekomendasi laptop murah" → `FOOD` (positif palsu), "kandungan gizi tahu" → `CLARIFY_FOOD` ("tahu" dianggap kata henti). Keduanya tidak berbahaya dan belum diperbaiki.

## 6. Yang harus dilakukan pemilik

1. Tinjau teks tujuan consent `ai_message_understanding` bersama tinjauan hukum consent.
2. Tetapkan apakah judge perlu model terpisah (lebih kecil atau lain) agar kegagalan bersama tidak terjadi.
3. Perbaikan "tahu" sebagai kata henti dan positif palsu "rekomendasi" untuk barang non-makanan bisa masuk fase berikutnya.

## 7. Rollback

Migrasi `20261112150000_p10_hybrid_agent` menambah tabel, kolom nullable, dan memperluas CHECK; pembaruan `dish-classifier` ke `DEPRECATED` bisa dikembalikan lewat `set-model-status.ts`. Mematikan tanpa rollback: `feature-flag.ts set llm_router off`.
