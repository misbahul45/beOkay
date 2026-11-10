# Matriks perjalanan E2E P2 (E2E-01…12)

Diperbarui 10 November 2026. Status memakai kata yang jujur: **TERBUKTI** (dijalankan dan diamati), **TERUJI OTOMATIS** (tes lulus), **SEBAGIAN**, **BELUM**.
Backend: `server/tests/integration/*.test.ts` (Docker, DB uji terisolasi). Flutter: `app/test/flows/*.dart`. Emulator: Pixel_4, Appium MCP, API dev + layanan nyata (Mistral, Modal).

| ID | Perjalanan | Bukti | Status | Catatan / celah |
|---|---|---|---|---|
| E2E-01 | Nutrisi personal | `agent.test.ts` "Alur penuh: usulan bersumber…"; `coach_test.dart`; emulator (permintaan → kartu bersumber TKPI → simpan → rencana) | TERBUKTI | Tidak ada nilai gizi karangan: nilai kosong tampil "tidak tersedia". "Modal ranker" tidak ada: peringkat aturan tetap (model hanya mengenali foto). |
| E2E-02 | Aktivitas adaptif | `agent-activity.test.ts`; `p2-closed-loop.test.ts` (hasil aktivitas terukur); emulator (rencana → selesai → "Terbukti: sesi sejenis tercatat") | TERBUKTI | Tanpa nilai wearable karangan; manual cukup. Tidak ada nasihat medis (eskalasi/cedera diblokir). |
| E2E-03 | Personalisasi tertutup | `agent.test.ts` "Lingkar umpan balik…"; `p2-closed-loop.test.ts` "E2E-12 inti" (bonus dari makanan terukur, ditarik saat catatan diarsipkan) | TERUJI OTOMATIS | Aturan `pref-rules-v2` terdokumentasi dan dapat dijelaskan; bukan pembaruan model. |
| E2E-04 | Modal gagal | `ml.test.ts` (assist: 503, versi tak cocok → null), `modal-client.test.ts` (retry, circuit breaker); emulator: cold start 11 dtk → hasil utama tetap tampil tanpa perkiraan | TERBUKTI | Ada pemanasan (`/api/me/ml/warmup`) untuk mengurangi cold start. |
| E2E-05 | Agen restart | **Restart proses API sungguhan** (skrip satu kali): run menunggu → `docker compose restart api-test` → keputusan dikirim dua kali dengan operationId sama → `replayed:true`, 1 `planned_meal`, 1 peristiwa outbox | TERBUKTI | Skrip tidak disimpan di repo (aturan skrip sementara); tes otomatis `agent.test.ts` "run macet" tetap simulasi. |
| E2E-06 | Konfirmasi ganda | `agent.test.ts` "Persetujuan bersamaan…"; `p2-closed-loop.test.ts` (dedupe outbox); `coach_test.dart` (operationId dipakai ulang) | TERUJI OTOMATIS | |
| E2E-07 | Penarikan consent | `agent.test.ts` "Penarikan consent…"; `p2-closed-loop.test.ts` (SSE tidak membocorkan saran setelah pencabutan; rekonsiliasi berhenti) | TERUJI OTOMATIS | "Cache konteks": tidak ada cache lintas-run; setiap run membaca ulang. |
| E2E-08 | Komunitas opt-in | `community.test.ts`; `community_test.dart`; emulator (provinsi → gabung → alias → tantangan → progres) | TERBUKTI | Papan peringkat di perangkat hanya sampai penekanan kohort (1 peserta). Opt-in papan peringkat di perangkat ditolak tanpa consent (dikonfirmasi 403). |
| E2E-09 | Koreksi papan peringkat | `community.test.ts` "Koreksi sumber: arsip aktivitas membalik poin…" | TERUJI OTOMATIS | Tidak diuji di perangkat. |
| E2E-10 | Keamanan lintas akun | `agent.test.ts` "Isolasi akun…"; `community.test.ts` (tanpa nama/surel di papan, skema tanpa FK ke data kesehatan); `p2-closed-loop.test.ts` (parent run orang lain → 404; `/pending` tidak bocor) | TERUJI OTOMATIS | Tidak ada uji penetrasi terpisah. |
| E2E-11 | Mobile restart | Server: `/api/me/agent/pending` (tes). Flutter: `coach_test.dart` (dua tes). **Emulator: proses aplikasi dimulai ulang → layar Asisten memulihkan saran yang menunggu** | TERBUKTI | Saran dipulihkan dari server (sumber kebenaran), tidak dari penyimpanan lokal. |
| E2E-12 | Loop produk penuh | Catatan makan → rencana diterima → hasil terukur → bonus peringkat beralasan (`p2-closed-loop.test.ts`); emulator: aktivitas terukur, pengingat dijadwalkan | SEBAGIAN | "Weekly Review" dan "Goal/Plan" ke tujuan perilaku tidak terhubung ke agen secara otomatis; ringkasan mingguan P1 ada tetapi tidak dipanggil oleh agen. Hasil terukur memakai pencocokan nama yang heuristik. |

## Yang tidak dijalankan
- Uji penetrasi/ZAP; uji beban; evaluasi trajektori LLM dengan juri (hanya aturan deterministik: gerbang keluaran, tanpa angka baru, tanpa klaim terlarang).
- Push FCM nyata (terblokir: aplikasi belum didaftarkan di Firebase; `applicationId` masih `com.example.app`).
