# Audit fitur dan peta video demo beOkay — 14 November 2026

> Tujuan: video demo ujung ke ujung yang memperlihatkan semua fitur, menjual nilai, keunikan, dan kapabilitas beOkay. Dokumen ini hanya analisis dan rencana; tidak ada kode atau aplikasi yang diubah, dan tidak ada yang dijalankan di perangkat saat audit.
> Pelengkap: [beokay-4.0-report.md](../reports/beokay-4.0-report.md) (bukti uji), [beokay-4.0-ecosystem.md](../architecture/beokay-4.0-ecosystem.md) (arsitektur), [beokay-4.0-clinical-review-packet.md](../reports/beokay-4.0-clinical-review-packet.md) (batas konten).

## 0. Kesimpulan

1. **Produknya cukup lengkap untuk video ujung ke ujung.** Tujuh butir "belum ada" di [gap-analysis-2026-11-12.md](gap-analysis-2026-11-12.md) yang saya periksa ternyata sudah ada di kode 4.0: catat satu ketukan, dikte suara, CGM, edukasi, pendamping, kunci aplikasi, PDF ringkasan. Butir lain di dokumen itu tidak saya periksa satu per satu, jadi dokumen itu **jangan dipakai sebagai daftar fitur**.
2. **Yang dijual bukan "ada AI", tetapi kendali dan kejujuran**: keselamatan deterministik sebelum model bahasa, model hanya mengusulkan lalu pengguna memutuskan dengan kuitansi, data yang tidak diketahui tetap kosong, persetujuan yang berlaku seketika saat ditarik, dan ingatan asisten yang bisa dilihat, dijeda, dan dihapus. Ini yang membedakan beOkay dari aplikasi pencatat lain (bagian 2).
3. **Struktur video**: master ±6 menit (16 adegan, S00–S15), potongan 90 detik, dan enam klip 15–20 detik, mengikuti urutan bagian template `media-video-project-demo` (bagian 5–6).
4. **Tiga penghalang produksi yang nyata** (bagian 7): tidak ada skrip data demo (akun kosong tidak menjual), konten edukasi dan jalur pencegahan disembunyikan di produksi (belum ditinjau klinisi), dan belum ada uji di ponsel fisik atau jam tangan.
5. **Batas klaim ketat** (bagian 4): tidak boleh ada klaim menurunkan gula darah, "ditinjau dokter", "mendukung jam tangan", integrasi SATUSEHAT, atau akurasi foto makanan.
6. **Keputusan yang butuh Anda** ada di bagian 9.

## 1. Metode dan batas audit

| Hal | Isi |
|---|---|
| Indeks | `codebase-memory-mcp`, proyek `home-misbahul45-code-beOkay`: 10.323 simpul, 51.051 sisi, status `ready`; TypeScript 373 berkas, Dart 286, SQL 37 |
| Inventaris | 51 folder fitur di `server/src/features`, 40 folder fitur di `app/lib/features`, 77 kelas layar/halaman/lembar (`*Screen`, `*Page`, `*Sheet`) |
| Rute | Graph mencatat 184 simpul `Route`, **termasuk jalur dari tes dan URL di compose**; itu bukan jumlah endpoint produksi. Rujukan jumlah resmi: `docs/api/endpoint-reference.md` |
| Cakupan parsial | 51 berkas tercatat `parse_partial`: migrasi SQL, runner native Linux/Windows, dan sebagian kecil berkas TypeScript (mis. `activity.repository.ts`, `jobs.service.ts`). Tidak memengaruhi inventaris fitur; klaim yang menyentuh berkas itu saya periksa langsung |
| Angka uji | Dikutip dari README (14 Nov): backend 462 tes/81 berkas, Flutter 251 tes, Bruno 120/120, uji asap produksi 20/20. **Tidak saya jalankan ulang.** Hitungan berkas di disk cocok: 81 berkas tes backend, 39 berkas tes Flutter |
| Status "SIAP" | Berarti ada di kode dan dilaporkan teruji. Bukan berarti sudah saya lihat berjalan |
| Tidak dicakup | Menjalankan aplikasi, merekam layar, menilai tampilan visual, uji ponsel fisik |

## 2. Keunikan yang bisa dijual

Diurutkan menurut kekuatan cerita di video. Setiap baris punya bukti di kode dan cara memperlihatkannya di layar.

| # | Keunikan | Bukti | Cara diperlihatkan | Kalimat aman |
|---|---|---|---|---|
| U1 | **Keselamatan di luar model bahasa.** Pertanyaan dosis, diagnosis, atau gejala darurat dicegat aturan deterministik sebelum model bahasa menyentuhnya, termasuk bahasa gaul dan salah ketik | `agent.safety.ts` (`safety-policy-v2`, 10 kode, normalisasi alias Indonesia); `tests/adversarial/agent-adversarial.test.ts` (8 skenario; satu kebocoran nyata ditemukan saat menulisnya dan ditutup) | Asisten dijawab arahan ke tenaga kesehatan; Spark berganti ke keadaan "!" yang statis; kartu Beranda menunda saran kebiasaan | "beOkay tidak memberi saran obat atau dosis" |
| U2 | **Model hanya mengusulkan; kamu yang memutuskan, dengan kuitansi.** Rekomendasi menunggu persetujuan, dan tindakan hanya berjalan lewat keputusan `ACCEPT` bertanda `operationId` | `agent.fsm.ts` (16 keadaan, `authorize(receipt)`); 11 alat baca, 7 butuh konfirmasi, 10 terlarang di `agent.tools.ts`; `tests/e2e/demo-4.0.test.ts` | Kartu usulan → Terima → rencana terbuat; Spark "?" saat menunggu | "Asisten mengusulkan, kamu yang menyetujui" |
| U3 | **Kosong tidak sama dengan nol.** Nilai tak diketahui tetap `NULL`; hari tanpa data perangkat tidak dihitung "tidak aktif"; tidur dari dua perangkat dihitung sekali | `devices/quality.*` (7 status: OK, PARTIAL, NO_DATA, NOT_CONNECTED, STALE, CONFLICT, IMPLAUSIBLE); `daily-facts` (`unionMinutes`); `score-v2` tidak mengurangi untuk hari istirahat | Layar status perangkat: hari kosong berlabel "belum ada data"; dua asal tidur tumpang tindih → tinjau, bukan dobel | "Hari tanpa catatan bukan kegagalan" |
| U4 | **Persetujuan per tujuan yang berlaku seketika.** Mencabut `personalized_ai` langsung menolak usulan ingatan, menjeda ingatan aktif, dan membatalkan rekomendasi terbuka | `consent.*`; `p12-ecosystem` C9; `demo-4.0.test.ts` baris kasus negatif | Cabut persetujuan → tanya Asisten → balasan "butuh persetujuan"; buka Ingatan → status dijeda | "Persetujuan bisa ditarik kapan saja dan berlaku segera" |
| U5 | **Ingatan asisten yang transparan.** Usulan → konfirmasi → konflik berdampingan (TERSIMPAN vs BARU) → jeda → riwayat; ada usulan turunan dari catatan sendiri | `memory.service.ts`, `memory_screen.dart`; memori turunan (≥ 4 sesi dan ≥ 60% di satu bagian hari dalam 28 hari) | Ucapkan kebiasaan → kartu usulan → Simpan → saran berikutnya memuat "Aku ingat…" | "Asisten hanya mengingat yang kamu setujui" |
| U6 | **Tiga jalur, konten tidak bocor.** Jalur hanya dari pernyataan pengguna; konten diabetes tidak pernah sampai ke jalur lain; tipe 1, di bawah 18, atau usia tak diketahui = pencatatan saja | `cohort.policy.ts` (`determineJourney`), peta `MODULE_JOURNEYS` dan `STRATEGY_JOURNEYS` | Dua akun rekaan, daftar edukasi berdampingan | "Jalur ditentukan dari ceritamu, bukan ditebak dari data" |
| U7 | **Jujur sampai abstain.** Jawaban membawa label kepastian dan sumber; bila tidak ada bacaan yang cocok, asisten menolak menjawab | `certaintyOf`, `knowledge.service.ts`, bagian `evidence` di `chat_parts.dart`; produksi abstain sampai ada konten `REVIEWED` | Chip kepastian pada jawaban; satu adegan sengaja menampilkan abstain | "Kalau tidak tahu, asisten bilang tidak tahu" |
| U8 | **Privasi sosial.** Papan peringkat dan misi tim hanya muncul bila ≥ 5 peserta; tidak pernah ada nama atau angka kesehatan | `scoring.v2.ts`, `GET /api/me/challenges/:id/team` | Tampilkan keadaan "minimal 5 anggota" lalu keadaan terisi | "Semangat bersama tanpa membuka angka kesehatan siapa pun" |
| U9 | **Beban catat minimal dan tetap berfungsi luring.** Satu ketukan, dikte, foto, barcode, antrean luring idempoten | `quick_repeat_card.dart`, `voice_input.dart`, `sync_screen.dart`; kunci dedupe peristiwa | Catat dalam hitungan detik; mode pesawat → catat → tersambung → terkirim sekali | "Catat dalam hitungan detik, tanpa sinyal pun" |
| U10 | **Bisa dibawa ke kontrol dan keluar sistem.** Ringkasan PDF, tautan baca-saja dengan QR, ekspor JSON dan FHIR R4 (Patient + Observation dengan kode LOINC) | `summary_pdf.dart`, `companion.dart`, `export/fhir.model.ts` | Buka PDF, pindai QR ke halaman web baca-saja, tunjukkan potongan bundel FHIR | "Datamu milikmu dan bisa dibawa" |
| U11 | **Kedalaman rekayasa.** Peristiwa beramplop di transaksi yang sama, proyeksi harian yang bisa diputar ulang identik, migrasi dengan skrip turun, uji pulih cadangan, deploy serverless | laporan 4.0 §1–§2; `server/prisma/rollback/`; `backup-restore-check.sh` | Kartu bukti di adegan penutup | Hanya angka yang tertulis di README |

Konteks lokal yang boleh disebut sebagai nilai tambah: referensi gizi TKPI 2017 dan hidangan Indonesia terkurasi, antarmuka dan keselamatan berbahasa Indonesia, ekspor FHIR R4 sebagai kesiapan interoperabilitas.

## 3. Pelacak fitur → adegan

Status: **SIAP** = ada di kode dan dilaporkan teruji · **DATA** = butuh data contoh · **FLAG** = butuh sakelar dev · **VERIF** = verifikasi di layar sebelum rekam · **TAHAN** = jangan diklaim atau diperlihatkan sebagai kemampuan.

| ID | Fitur | Bukti (kode / rute) | Adegan | Status |
|---|---|---|---|---|
| F01 | Mode coba tanpa akun | `guest/guest_mode.dart` (`GuestHomeScreen`, `GuestRecordSheet`) | S03 | SIAP; alur "pindahkan catatan" setelah daftar hanya terbukti di desain 32-n → VERIF |
| F02 | Jalur dan pernyataan risiko | `cohort.policy.ts`, `journey_screen.dart`, `health_profile_screen.dart`, `PUT /api/me/health-profile` | S04 | SIAP |
| F03 | Persetujuan per tujuan, tarik | `consent_screen.dart`, `consent_management_screen.dart`, `/api/me/consents`, `/consents/withdraw` | S04, S09 | SIAP |
| F04 | Edukasi 13 modul | `education.dart`, `/api/education/modules` | S04 | FLAG (produksi menyembunyikan draf) |
| F05 | Glukosa mg/dL dan mmol/L, peringatan di bawah 70 atau 300 | `glucose_form_screen.dart`, `glucose_models.dart` (`glucoseAlertFor`) | S05 | SIAP |
| F06 | Makan: ketik, kalimat, dikte | `meal_form_screen.dart`, `voice_input.dart` (`MicButton`), `meal-text.parser.ts` | S05 | SIAP; dikte butuh pengenal suara di perangkat → VERIF |
| F07 | Makan: foto, barcode, label gizi | `scan/photo_result_screen.dart`, `food_review_screen.dart`, `barcode_scan_screen.dart` | S05 | DATA; **TAHAN klaim akurasi** |
| F08 | Sering dicatat / ulangi | `quick_repeat_card.dart`, `GET /api/me/quick-record/suggestions` | S05 | DATA (butuh riwayat) |
| F09 | Antrean luring dan sinkron | `sync_screen.dart`, `/api/me/sync/operations` | S06 | SIAP |
| F10 | Check-in tenaga | `POST /api/me/checkins/energy` | S07 | SIAP |
| F11 | Langkah berikutnya + chip alur | `next-action.service.ts`, `next_action_section.dart` | S07 | SIAP (diuji Appium di emulator) |
| F12 | Spark, 6 keadaan | `core/widgets/beokay_spark.dart` | S07, S08 | SIAP |
| F13 | Progres `score-v2`, rekor, kembali-setelah-jeda | `community/scoring.v2.ts` | S07 | DATA |
| F14 | JITAI v3, notifikasi, push FCM | `intervention.policy.v3.ts`, `notifications_screen.dart` | S07 | VERIF; push teruji di emulator, belum di ponsel fisik |
| F15 | Asisten: rute dan keselamatan | `agent.safety.ts`, `coach_screen.dart` | S08 | SIAP |
| F16 | Rekomendasi → kuitansi → FSM | `agent.fsm.ts`, `POST /api/me/agent/recommendations/:id/decision` | S08 | SIAP |
| F17 | Label kepastian dan abstain | `chat_parts.dart` (`evidence`), `knowledge.service.ts` | S08 | SIAP; abstain muncul di produksi |
| F18 | Draf makan dari kalimat | `/api/me/meal-drafts`, `meal-drafts.*` | S05, S08 | SIAP |
| F19 | Ingatan: usul, konflik, jeda, riwayat, turunan | `memory.service.ts`, `memory_screen.dart` | S09 | DATA (memori turunan butuh ≥ 4 sesi pagi) |
| F20 | Status perangkat dan Health Connect | `device_status_section.dart`, `/api/me/devices/status`, `/api/me/device-import` | S10 | DATA; **TAHAN klaim jam tangan** |
| F21 | Tren dan pasangan glukosa–makan | `trends_screen.dart`, `/api/me/glucose/:id/context`, `/api/me/meals/:id/context` | S11 | DATA |
| F22 | CGM impor CSV, ringkasan 14 hari | `cgm.dart`, `/api/me/cgm/imports`, `/cgm/summary` | S11 | DATA (butuh berkas CSV contoh) |
| F23 | Ringkasan PDF | `share/data/summary_pdf.dart`, `summary_report_screen.dart` | S11 | SIAP |
| F24 | Pendamping: tautan baca-saja dan QR | `companion.dart`, `/api/me/companions`, `/s/:token` | S11 | SIAP |
| F25 | Ekspor JSON dan FHIR R4 | `export_section.dart`, `fhir.model.ts`, `/api/me/export/fhir` | S11 | SIAP; **TAHAN klaim SATUSEHAT** |
| F26 | Komunitas, tantangan, misi tim | `community_screen.dart`, `challenge_screen.dart`, `/api/me/communities*`, `/challenges/*` | S12 | DATA (butuh 5 akun contoh) |
| F27 | Obat dan konfirmasi dari notifikasi | `medication_screen.dart`, `/api/me/medications/today` | S13 | SIAP |
| F28 | Vital dan hasil lab (tanpa interpretasi) | `clinical_screen.dart`, `/api/me/vitals`, `/labs` | S13 | SIAP |
| F29 | Tujuan dan check-in tujuan | `goals_screen.dart`, `/api/me/goals` | S13 | SIAP |
| F30 | Pengingat | `reminders_screen.dart`, `/api/me/reminders` | S13 | SIAP |
| F31 | Preferensi makanan | `food_preferences_screen.dart` | S13 | SIAP |
| F32 | Kunci aplikasi biometrik | `app_lock/app_lock.dart` (dipasang di `app.dart`) | S13 | SIAP |
| F33 | Ekspor dan hapus akun | `privacy_data_screen.dart` (`DeleteAccountScreen`), `/api/me/account/delete` | S13 | SIAP |
| F34 | Refleksi mingguan dan coaching | `reflection_screen.dart`, `coaching_screen.dart`, `/api/me/coaching*` | S07, S08 | SIAP |
| F35 | Landing page dan unduh APK satu URL | `landing/`, `/beokay.apk` | S01, S15 | SIAP |
| F36 | Bukti rekayasa | README §Status; laporan 4.0 | S14 | SIAP; angka dikutip, bukan dijalankan ulang |

**Sengaja tidak dimasukkan ke video**: perencana LLM bayangan (mati bawaan, usulannya tidak dijalankan), `baseline-v1` (SHADOW), model foto makanan riset (`RESEARCH_ONLY`), metrik retrieval (n = 18 kueri; recall@3 held-out 0,833 terlalu kecil sampelnya untuk jadi klaim di video utama). Semuanya boleh muncul di dek teknis dengan catatan batas.

## 4. Batas klaim

| Boleh | Jangan |
|---|---|
| "Bukan alat diagnosis; tidak memberi saran obat atau dosis" | "Menurunkan gula darah / HbA1c", "mencegah diabetes atau komplikasi" |
| "Asisten mengusulkan, kamu yang memutuskan" | "Dokter AI", "prediksi gula darah", saran dosis dalam bentuk apa pun |
| "Membaca data dari Health Connect" (data contoh diberi label) | "Mendukung jam tangan" (belum ada uji perangkat nyata; C13 UNVERIFIED) |
| "Ekspor FHIR R4" | "Terintegrasi SATUSEHAT" (butuh faskes mitra; baru ekspor) |
| "Konten edukasi masih draf, menunggu tinjauan klinisi" | "Ditinjau atau disetujui dokter/ahli gizi" |
| "Perkiraan gizi, berlabel kepastian" | "Mengenali makanan Indonesia dengan akurat" (belum ada validasi) |
| "Tahap pengembangan, belum dipakai dalam pilot klinis" | "Dipakai pengguna nyata", testimoni, atau angka dampak |
| Angka uji dengan sumber README dan tanggal | Angka kinerja model (evaluasi perilaku memakai data sintetis, bukan kinerja) |
| "Hari tanpa catatan bukan kegagalan" | Peringkat berdasarkan nilai glukosa, berat, atau kalori (tidak ada di produk) |

Menyebut keterbatasan di penutup justru menambah kepercayaan; semua ini selaras dengan prinsip di `AGENTS.md` (tanpa klaim efektivitas klinis) dan temuan audit sebelumnya (perilaku membaik bukan berarti hasil klinis membaik).

## 5. Struktur video

Mengikuti kontrak template `media-video-project-demo`: urutan bagian tetap **intro → what → architecture → running demo → result → outro**; durasi boleh diperpanjang. Slot "running demo" dipecah menjadi bab. Aturan template yang ikut berlaku: tidak mengubah aplikasi demi tampilan video, dan tidak membuat layar UI sintetis. Gambar desain FigCraft (`design/exports/*.png`) hanya boleh dipakai sebagai adegan "proses desain" yang diberi label, tidak sebagai pengganti layar aplikasi.

**Tokoh rekaan (dua akun contoh, diberi label "data contoh" di layar):**
- Persona A, jalur Pencegahan: hanya untuk adegan jalur dan edukasi (S04).
- Persona B, dukungan T2DM: semua adegan pencatatan, Asisten, ingatan, perangkat, dan laporan.

**Alur cerita:** masalah (aplikasi kesehatan sering menebak dan menggurui) → janji (beOkay bertanya, mencatat, mengusulkan; kamu yang memutuskan) → bukti di layar (U9 → U2 → U1 → U5/U4 → U3 → U10) → bukti rekayasa → ajakan unduh.

**Tiga luaran:**

| Luaran | Durasi | Isi |
|---|---|---|
| Master | ±6:02 | 16 adegan (S00–S15) di bagian 6 |
| Potongan 90 detik | 1:30 | S00 4 dtk, S01 8, S05 14 (catat satu ketukan dan dikte), S07 12, S08 22 (keselamatan dan terima usulan), S09 8, S10 8, S14 8, S15 6 |
| Klip 15–20 detik | 6 klip | "Tahu kapan harus diam" (U1); "Kosong bukan nol" (U3); "Kamu pegang ingatannya" (U5); "Satu langkah, bukan seratus notifikasi" (F11); "Catat dalam detik" (U9); "Privasi yang bisa ditarik" (U4) |

Varian vertikal/horizontal/persegi dipilih lewat preset ekspor, tidak diubah ukurannya diam-diam.

## 6. Peta adegan (master)

| ID | Waktu | Bagian | Fitur | Aksi di layar | Narasi inti | Prasyarat | Sumber rekam |
|---|---|---|---|---|---|---|---|
| S00 | 0:00–0:06 | intro | F35 | Logo beOkay, judul | — | Aset logo `landing/public/img` | Aset repo |
| S01 | 0:06–0:20 | what | F35 | Hero landing dengan ponsel 3D yang menampilkan Beranda asli; strip tiga jalur | "Ekosistem kebiasaan sehat: pencegahan, dukungan diabetes tipe 2, gaya hidup sehat. Bukan alat diagnosis." | Landing di produksi atau pratinjau lokal | Browser |
| S02 | 0:20–0:38 | architecture | F36 | Satu diagram: catatan → peristiwa → proyeksi harian → skill terdaftar → persetujuanmu → ingatan | "Setiap catatan menjadi satu peristiwa; setiap saran menunggu persetujuanmu." | Diagram dari alur di `beokay-4.0-ecosystem.md`, bukan UI buatan | Grafik statis |
| S03 | 0:38–1:00 | demo Bab 1 | F01 | Pasang → "Coba dulu tanpa akun" → catat satu hal di lembar catat tamu | "Mulai mencatat sebelum membuat akun." | Pemasangan bersih | Emulator |
| S04 | 1:00–1:28 | demo Bab 2 | F02, F03, F04 | Pertanyaan "pernah diberi tahu tenaga kesehatan…" → layar Jalurmu → persetujuan per tujuan → layar terbelah daftar edukasi dua persona | "Jalur ditentukan dari ceritamu. Konten diabetes tidak pernah sampai ke jalur lain." | Persona A dan B; stack dev dengan draf edukasi nyala dan label "draf" | Emulator, stack lokal |
| S05 | 1:28–2:13 | demo Bab 3 | F05–F08, F18 | Kartu "Sering dicatat" satu ketukan → dikte kalimat makan → draf → konfirmasi → pindai barcode dan foto (label "perkiraan") → ketik glukosa di bawah 70 → peringatan → ganti ke mmol/L | "Mencatat tidak boleh lebih berat daripada hidup yang dicatat." | Riwayat makan; kamera/barcode produk nyata; kunci Mistral aktif | Ponsel atau emulator |
| S06 | 2:13–2:27 | demo Bab 3b | F09 | Mode pesawat → catat glukosa → status antre → tersambung → terkirim | "Tanpa sinyal pun tercatat; sekali tersambung, terkirim satu kali." | — | Emulator |
| S07 | 2:27–3:00 | demo Bab 4 | F10–F14, F34 | Kartu Langkah berikutnya + chip alur → check-in "Lelah" → progres mingguan → notifikasi pengingat | "Satu langkah kecil, bukan seratus notifikasi. Hari tanpa catatan bukan kegagalan." | Rencana aktif; data 14 hari | Emulator |
| S08 | 3:00–3:48 | demo Bab 5 | F15–F18, F12 | Minta ide olahraga ringan → kartu usulan (Spark "?") → Terima → rencana terbuat; lalu pertanyaan dosis obat → arahan ke tenaga kesehatan (Spark "!"); lalu topik tanpa bacaan tertinjau → abstain | "Model bahasa mengusulkan. Aturan dan kamu yang memutuskan. Kalau tidak tahu, bilang tidak tahu." | Persona B; ≥ 3 pengambilan (teks model bervariasi, rute dan keselamatan deterministik) | Emulator |
| S09 | 3:48–4:16 | demo Bab 6 | F19, F03 | Ucapkan kebiasaan → kartu usulan → Simpan → minta ide lagi → "Aku ingat…"; kartu konflik; Jeda; Riwayat; cabut persetujuan AI personal → Asisten minta persetujuan | "Asisten hanya mengingat yang kamu setujui, dan berhenti saat kamu mencabutnya." | ≥ 1 rencana diterima | Emulator |
| S10 | 4:16–4:34 | demo Bab 7 | F20 | Status perangkat: cakupan 14 hari, hari kosong "belum ada data", tidur dua asal tumpang tindih → perlu ditinjau, sakelar persetujuan data perangkat | "Kosong bukan nol. Dua perangkat, satu malam, dihitung sekali." | Data impor contoh lewat API (diberi label); **tanpa gambar jam tangan** | Emulator |
| S11 | 4:34–5:02 | demo Bab 8 | F21–F25 | Tren → detail makan dengan pasangan glukosa ("dua angka, bukan sebab-akibat") → impor CSV CGM → PDF ringkasan → QR → halaman web baca-saja → potongan bundel FHIR | "Datamu bisa dibawa ke kontrol, tanpa kehilangan kendali." | 14 hari glukosa + makan; berkas CSV contoh; ponsel kedua atau browser untuk QR | Emulator + browser |
| S12 | 5:02–5:14 | demo Bab 9 | F26 | Alias → tantangan → keadaan "minimal 5 anggota" → keadaan terisi: hanya jumlah hari tim, tanpa nama | "Semangat bersama tanpa membuka angka kesehatan siapa pun." | 5 akun contoh bergabung dengan persetujuan tantangan | Emulator |
| S13 | 5:14–5:32 | demo montase | F27–F33 | Cepat: obat (konfirmasi dari notifikasi), vital dan lab, tujuan, pengingat, preferensi makanan, kunci aplikasi, ekspor dan hapus akun | "Dan semua yang menopangnya, dengan kendali di tanganmu." | Data contoh | Emulator |
| S14 | 5:32–5:52 | result | F36 | Kartu bukti: 462 tes backend, 251 tes Flutter, koleksi API 120/120, uji asap produksi 20/20, uji pulih cadangan, migrasi dengan skrip turun | "Dibangun untuk diuji, bukan hanya untuk dilihat." | Angka dikutip dari README 14 Nov; opsional rekam satu proses uji di Docker | Kartu statis / terminal |
| S15 | 5:52–6:02 | outro | F35 | Logo, "Tahap pengembangan, bukan pengganti saran tenaga kesehatan", tautan unduh | Ajakan unduh APK | Versi APK dan tautan dari README | Aset repo |

Setiap klip direkam per bab (satu berkas per adegan), sesuai urutan template, supaya mudah diambil ulang tanpa merekam semuanya lagi.

## 7. Kesiapan produksi

| # | Temuan | Tindakan |
|---|---|---|
| P1 | **Tidak ada skrip data demo.** Satu-satunya skrip yang menyebut "seed" adalah `scripts/eval/behavior-eval.ts` (fikstur evaluasi). Akun kosong tidak menjual | Tulis skrip di **scratchpad** (bukan di repo; aturan `AGENTS.md`) yang memanggil **API nyata** agar peristiwa dan proyeksi harian terisi lewat jalur resmi, bukan lewat SQL. Kata sandi dibangkitkan acak per eksekusi. Data minimum Persona B: 14–21 hari glukosa dengan variasi konteks, 2–3 makan per hari dari hidangan Indonesia, ≥ 4 sesi aktivitas pagi dalam 28 hari (memicu usulan ingatan turunan), satu rencana aktif, obat terjadwal, tidur dari dua asal yang tumpang tindih, berkas CSV CGM contoh; Persona A hanya profil; lima akun contoh untuk misi tim |
| P2 | Konten edukasi dan jalur pencegahan disembunyikan di produksi (`EDUCATION_INCLUDE_DRAFTS=false`); asisten abstain | Rekam di stack lokal dengan draf menyala dan label "draf, belum ditinjau klinisi", atau jadikan abstain sebagai adegan kejujuran (S08). Jangan tampilkan seolah sudah ditinjau |
| P3 | Belum ada uji di ponsel fisik, jam tangan, atau TalkBack; push teruji hanya di emulator (README, laporan 4.0 C13) | Jangan tampilkan atau sebut jam tangan. Rekam dikte suara dan Health Connect di perangkat yang mendukung; bila hanya emulator, jangan klaim "teruji di ponsel" |
| P4 | Target rekam | Disarankan: build **release** di emulator (resolusi tinggi) yang menunjuk API lokal (`--dart-define=API_BASE_URL=http://10.0.2.2:3000`) supaya tanpa pita debug; verifikasi email lewat Mailpit lokal. Produksi hanya untuk memeriksa landing, APK, dan CTA. Flutter berjalan di host, backend di Docker (aturan proyek) |
| P5 | Batas laju masuk 5 kali per menit (`auth.ts`, `/sign-in/email`) | Masuk sekali per persona dan simpan sesi; jangan merekam masuk berulang. Pengetikan Appium lewat `appium_set_value` (kuirk di memori) |
| P6 | Teks asisten tidak deterministik (Mistral) | ≥ 3 pengambilan untuk S08; rute dan jawaban keselamatan stabil sehingga aman diulang |
| P7 | Kebocoran data di rekaman | Tidak ada layar peluncur ponsel, notifikasi pribadi, atau email pemilik (`INCIDENT_EMAIL_TO`, `EMAIL_FROM`); semua akun rekaan. Ukuran teks sistem 1,0 dan dikembalikan bila diubah |
| P8 | `figcraft` gagal tersambung di sesi ini (`CONNECTION_CLOSED`) | Tidak diperlukan untuk video; ekspor desain yang ada sudah cukup bila dipakai sebagai adegan proses desain |
| P9 | Consent 1.1 meminta persetujuan ulang semua pengguna lama | Tidak memengaruhi akun baru; justru bisa dipakai di S04 |

## 8. Gap data bukti

- Laporan 4.0 menyatakan Level bukti 1 (fungsi teknis terbukti di lingkungan uji). Tidak ada klaim level 2–4. Video harus memakai bahasa yang sama.
- Demo 10 langkah di `tests/e2e/demo-4.0.test.ts` terbukti di level API; layar-layarnya diuji per widget, dan hanya Beranda, Ingatan, serta push yang dilaporkan diuji Appium di emulator. Alur lain (mis. dikte, barcode, CGM, QR) perlu diperiksa sekali jalan sebelum direkam.

## 9. Keputusan dan langkah berikutnya

**Keputusan yang diperlukan dari pemilik:**

1. **Audiens dan durasi.** Asumsi saya: penilai produk atau juri; master ±6 menit, potongan 90 detik, enam klip. Bila audiensnya investor atau dosen dengan batas waktu, rasio adegan S02/S13/S14 yang diubah, bukan urutannya.
2. **Target rekam.** Stack lokal dengan draf edukasi nyala (disarankan) atau produksi (konten pencegahan abstain).
3. **Persetujuan membuat skrip data demo** di scratchpad (P1). Ini langkah pertama yang tidak bisa dilewati.
4. **Pipeline XN-Motion.** Bila disetujui: `environment_check` → `project_create` → `project_inspect` (lokal, tanpa jaringan) → `features_extract` dan `feature_evidence` untuk menandai klaim → `brief_create` → `storyboard_generate` → `preview_generate`. `website_inspect` (jaringan) dan `render_start` final hanya setelah persetujuan Anda; persetujuan storyboard tidak akan saya berikan atas nama Anda.

**next_action:** setujui keputusan 1–3, lalu saya menulis skrip data demo di scratchpad dan menjalankan stack uji untuk memeriksa kesiapan tiap adegan berstatus VERIF sebelum ada rekaman.

Dokumen ini belum di-commit; commit dilakukan oleh pemilik.
