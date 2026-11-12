# Threat model Asisten beOkay (agen hibrida)

> Sejak 3.0 Fase 10 (A-7). Kerangka: OWASP Top 10 for LLM Applications 2025 (LLM01 Prompt Injection, LLM02 Sensitive Information Disclosure, LLM05 Improper Output Handling, LLM06 Excessive Agency, LLM07 System Prompt Leakage, LLM09 Misinformation, LLM10 Unbounded Consumption). Dokumen ini menggambarkan kode pada 12 November 2026, bukan rencana.

## 1. Prinsip yang dipertahankan

1. **Keputusan selalu deterministik.** Model bahasa hanya (a) menulis ulang penjelasan dari fakta yang sudah dipilih (`llm-text.ts`, sejak P2), (b) mengusulkan rute untuk pesan yang tidak dikenali aturan, dan (c) menilai apakah pesan harus ditahan (`intent-classifier.ts`, Fase 10). Model tidak pernah memanggil alat, memilih alat, menulis catatan, atau membuka rute yang ditolak aturan.
2. **Saringan keselamatan regex (`safety-policy-v2`) berjalan pertama.** Pesan yang diblokir tidak pernah dikirim ke model (diuji: 0 panggilan model).
3. **Judge hanya bisa menahan.** Hasil `HOLD` mengubah balasan menjadi kartu keselamatan atau "belum paham"; hasil `SAFE` tidak melonggarkan apa pun.
4. **Setiap usulan model dicatat** di `router_proposals` (rute, argumen, keyakinan, keputusan validasi, putusan judge, model, latensi) dan bisa diaudit; ikut ekspor dan retensi 90 hari.
5. **Data minimum ke pihak ketiga.** Pemahaman pesan butuh consent `ai_message_understanding`; yang dikirim hanya teks pesan yang tidak dikenali (≤ 600 karakter). Nama, surel, catatan kesehatan tidak dikirim.

## 2. Aset dan batas kepercayaan

| Masukan tak tepercaya | Masuk ke | Perlakuan |
|---|---|---|
| Teks pesan pengguna | `routeMessage` (regex), `createLlmRouter` (model) | regex dulu; pola injeksi (`INJECTION_PATTERN`) tidak dikirim ke model; teks dibungkus sebagai data JSON dengan pembatas `PESAN (data)` |
| Keluaran model pengklasifikasi | `validateProposal` | skema Zod ketat (kunci asing → tolak), daftar rute tertutup, keyakinan ≥ 0,6, kueri makanan wajib berupa kata dari pesan (≤ 4 kata, tanpa kata SQL/sistem), menit wajib tertulis di pesan dan 5–180, domain statistik dari enum |
| Keluaran model judge | `judgeSchema`, `heldRoute` | hanya `SAFE`/`HOLD` dan kategori enum; galat atau skema rusak → tidak ada rute |
| Usulan memori dari model | `validateProposal` + `memoryService.propose` | ≥ 50% kata penting harus ada di pesan, kata sensitif (obat, insulin, diagnosis, angka ≥ 3 digit, tautan) ditolak, kondisi sementara hanya dari daftar (puasa, flu, mudik); selalu `PROPOSED`, butuh ketukan pengguna, kedaluwarsa per jenis |
| Markdown halaman web (`search_web_nutrition`) | `parseNutritionPer100g` | parser deterministik, tidak pernah masuk prompt; nilai harus lolos batas dan konsistensi energi-makro |
| Teks OCR label | `parseLabel` | parser deterministik |
| Nama produk Open Food Facts/USDA | tampilan dan katalog pribadi | hanya data; tidak masuk prompt pengklasifikasi |
| Teks yang ditulis model (`llm-text.ts`) | `gateLlmText` | tanpa tautan/markup, tanpa angka baru, tanpa klaim terlarang, harus menyebut nama; gagal → templat |
| Isi ringkasan di halaman `/s/:token` | `share.page.ts` | semua nilai di-escape; CSP tanpa skrip dengan nonce gaya |

## 3. Alat dan hak minimum

| Alat (`agent.tools.ts`) | Intent yang boleh | Consent | Risiko utama | Kendali |
|---|---|---|---|---|
| `get_food_preferences` | NUTRITION_ALTERNATIVES | H + A | kebocoran preferensi | dibatasi `user_id` sesi |
| `get_personalization` | NUTRITION_ALTERNATIVES, ACTIVITY_PLAN | A | profil berlebihan | hanya token suka/tidak suka |
| `search_food_reference` | NUTRITION_ALTERNATIVES | H | kueri berisi injeksi | kueri sudah divalidasi dari teks; query SQL berparameter |
| `search_user_foods` | NUTRITION_ALTERNATIVES | H | akses katalog orang lain | `user_id` sesi |
| `get_activity_context` | ACTIVITY_PLAN | H | saran berlebihan | durasi dibatasi sesi terpanjang; kondisi sementara "kurang sehat" membatasi 10 menit |
| `get_behavior_goals` | ACTIVITY_PLAN | H | — | baca saja |
| `search_web_nutrition` | NUTRITION_ALTERNATIVES (atas permintaan) | H | LLM01 tidak langsung lewat halaman web | markdown hanya ke parser; sakelar `web_discovery`; batas laju |

Setiap alat punya `allowedIntents`, `requiredPermissions`, `timeoutMs`, `maxResultBytes`, dan anggaran panggilan per run (`MAX_TOOL_CALLS`). Pengklasifikasi tidak bisa menyebut nama alat (kunci asing ditolak skema).

## 4. Ancaman dan mitigasi (OWASP LLM 2025)

| ID | Ancaman | Mitigasi di kode | Bukti |
|---|---|---|---|
| LLM01 | Injeksi langsung lewat pesan ("abaikan instruksi", "SYSTEM:", "act as") | regex keselamatan → `INJECTION_PATTERN` → pembungkus data → validasi usulan → judge | `agent-hybrid.test.ts`: 100 kalimat injeksi, 0 pelanggaran; 9 usulan jahat yang lolos pra-saring ditolak validator |
| LLM01 | Injeksi tidak langsung lewat halaman web/OCR | konten pihak ketiga tidak pernah masuk prompt; parser deterministik | uji parser web dan label dengan teks injeksi |
| LLM02 | Teks kesehatan bocor ke pihak ketiga | consent terpisah; hanya pesan tak dikenali; tanpa identitas | `phase10.test.ts`: tanpa consent 0 panggilan model |
| LLM05 | Keluaran model dipakai mentah | semua keluaran model melewati skema dan gerbang; teks yang ditampilkan hanya dari templat atau `gateLlmText` | uji gerbang teks (tautan, markup, angka baru, klaim) |
| LLM06 | Agensi berlebihan | model tidak memilih alat; rute diterjemahkan ke jalur deterministik yang sama dengan regex; tidak ada penulisan tanpa ketukan pengguna | desain; `router_proposals` |
| LLM07 | Kebocoran prompt sistem | prompt tidak memuat rahasia atau data pengguna; jawaban model tidak pernah ditampilkan | desain |
| LLM09 | Saran medis keliru | regex keselamatan + judge `MEDICAL_ADVICE`/`URGENT`/`SELF_HARM` hanya menahan; Asisten tidak menjawab dari teks model | korpus keselamatan 99 kalimat; uji HOLD |
| LLM10 | Konsumsi tak terbatas | batas laju percakapan 30/10 menit; batas waktu 6 dtk; `max_tokens` 160; teks ≤ 600 karakter; sakelar `llm_router` | `phase10.test.ts` sakelar |

## 5. Risiko sisa

- Judge memakai model yang sama dengan pengklasifikasi; kegagalan bersama mungkin terjadi. Karena judge hanya menahan, kegagalannya membuat Asisten lebih sering berkata "belum paham", bukan lebih berbahaya.
- `INJECTION_PATTERN` berbasis kata kunci; parafrase injeksi bisa lolos ke model. Validator tetap menolak usulan yang tidak berdasar teks.
- Korpus injeksi dibangun dari 20 pembuka × 5 muatan; belum mencakup injeksi multi-giliran atau bahasa daerah.
- Kategori rute salah (mis. pertanyaan statistik dibaca sebagai HELP) tidak berbahaya tetapi menurunkan kegunaan; terukur di `scripts/eval/router-eval.ts`.

## 6. Cara memeriksa ulang

```bash
docker compose -f compose.test.yaml run --rm tester bun test tests/unit/agent-hybrid.test.ts tests/unit/router-corpus.test.ts tests/integration/phase10.test.ts
docker compose run --rm --no-deps api bun run scripts/eval/router-eval.ts
```
