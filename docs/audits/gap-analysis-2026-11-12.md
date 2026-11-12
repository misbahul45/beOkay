# Audit menyeluruh dan analisis gap beOkay — 12 November 2026

> Cakupan: seluruh repositori pada keadaan pohon kerja 12 Nov 2026 (HEAD `7d6e833` + perubahan Fase 7 yang belum di-commit). Metode: inventaris kode (bukan laporan lama), pembacaan ulang modul inti, hasil uji terakhir, dan pencocokan dengan bukti eksternal (pedoman klinis 2026, meta-analisis aplikasi diabetes, literatur JITAI, keselamatan agen LLM, kerangka bukti teknologi kesehatan digital). Audit ini **tidak mengubah kode**.
> Pelengkap dari [full-project-audit-2026-11-10.md](full-project-audit-2026-11-10.md) (temuan F-01…F-17, status terbaru di §0 dokumen itu). Dokumen ini fokus pada **gap** dan **arah perbaikan** di lima dimensi: UI, sistem, kapabilitas, hibrida agentik, dampak.

## 0. Ringkasan

beOkay hari ini adalah aplikasi pencatatan T2DM yang **disiplin secara data dan keselamatan** (nilai tak diketahui tetap kosong, saran tidak mengubah catatan, consent per tujuan, keselamatan deterministik di luar LLM) dengan cakupan fitur yang sudah luas untuk satu pengembang: 32 modul server, 64 model Prisma, 50 layar Flutter, 330 tes backend dan 210 tes Flutter yang hijau. Yang **belum** ada bukan fitur tambahan, melainkan empat hal yang menentukan apakah produk ini bisa membuktikan dirinya berguna:

| # | Gap terbesar | Dimensi | Mengapa menentukan |
|---|---|---|---|
| 1 | **Tidak ada pengukuran apa pun tentang pemakaian dan hasil**: tidak ada analitik keterlibatan (tujuan consent `product_analytics` ada tetapi tidak dipakai), tidak ada jangkar klinis (berat, HbA1c, tekanan darah tidak bisa dicatat), tidak ada kerangka evaluasi | Dampak | Tanpa ini pilot hanya menghasilkan cerita, bukan bukti; NICE ESF Tier B meminta bukti keterterimaan pengguna dan efektivitas |
| 2 | **Beban pencatatan belum diukur dan belum diminimalkan**: tidak ada catat-ulang satu ketukan dari riwayat/favorit, tidak ada input suara, Health Connect hanya membaca `WORKOUT`, tidak ada impor glukosa/langkah/tidur/berat | UI + Kapabilitas | Kepatuhan rata-rata aplikasi mHealth 56% dan turun seiring waktu; pencatatan manual adalah penghalang nomor satu yang dilaporkan literatur |
| 3 | **Asisten hibrida masih setengah hibrida**: router regex `router-v3` memutuskan maksud, LLM hanya menulis ulang teks; tidak ada evaluasi kualitas agen, tidak ada pencatatan paparan JITAI, memori hanya 5 jenis berbasis pola | Agentik | Parafrase di luar pola jatuh ke "Aku belum paham"; tidak ada cara mengukur apakah saran membantu |
| 4 | **Produk berdiri sendiri**: tidak ada laporan untuk klinisi, tidak ada berbagi ke keluarga/pendamping, tidak ada tautan ke Prolanis/SATUSEHAT, tidak ada konten edukasi terstruktur (DSMES) | Kapabilitas + Dampak | Konteks Indonesia: dukungan keluarga dan akses faskes adalah penghambat kepatuhan Prolanis yang dilaporkan; ADA 2026 merekomendasikan DSMES digital |

Arah yang diusulkan (§6): **Fase 8 — "Ukur dan ringankan"** (analitik berbasis consent, jangkar klinis, catat cepat, tujuan adaptif), lalu Fase 9 sinyal perangkat, Fase 10 hibrida agentik v2, Fase 11 ekosistem. Setiap fase memiliki ukuran keberhasilan yang bisa dihitung dari data yang sudah ada atau yang diusulkan.

## 1. Potret sistem saat ini (terverifikasi dari kode)

| Lapisan | Fakta |
|---|---|
| Server | Bun + TypeScript, 32 modul fitur, 14.853 baris (`src/`, tanpa generated), 27 migrasi, 64 model Prisma, satu proses (HTTP + pekerja push/outbox/notifikasi/siklus tantangan + WebSocket) |
| Aplikasi | Flutter, 34.244 baris, 27 fitur, 50 layar, 57 rute; hanya `id_ID`; antrean offline untuk 5 domain (`meal`, `glucose`, `activity`, `medication_intake`, `goal_checkin`) |
| Uji | backend 330 (65 berkas), Flutter 210 (33 berkas); CI ditulis, belum pernah berjalan |
| Data pengguna | profil kesehatan hanya: status diagnosis, tipe, tahun diagnosis, konteks pengobatan. **Tidak ada** berat, tinggi, lingkar pinggang, tekanan darah, HbA1c, daftar komplikasi |
| Sumber data | manual (semua domain), Health Connect (**hanya `WORKOUT`**), OCR label dan foto makanan (Mistral), barcode (OFF), TKPI + OFF/USDA + web (Firecrawl) |
| Asisten | `router-v3` regex → rute (SAFETY, STATS, FOOD, ACTIVITY_PLAN, MEAL_LOG, COMMUNITY, REFLECTION, …); 7 alat deny-by-default dengan anggaran; LLM (Mistral) hanya menulis ulang teks yang sudah lolos gerbang; memori 5 jenis berbasis pola; JITAI 5 pemicu, kanal in-app + notifikasi |
| Keselamatan | `safety-policy-v2` (10 aturan, 99 kalimat korpus), `explanationIsSafe`, `gateLlmText`; belum ditinjau klinisi |
| Statistik | `stats-v1` (median glukosa puasa/pasca makan, aktivitas, gizi, obat, cakupan catatan); perbandingan dua periode; **tidak ada baseline pribadi longitudinal** |
| Komunitas | alias, opt-in, tantangan berulang, papan peringkat kohort ≥ 5, pengakuan usaha; tidak ada moderasi/lapor |
| Operasi | log JSON per permintaan; tidak ada metrik/jejak/alarm; feature toggle hanya lewat env (butuh restart); cadangan ada skripnya, belum dijadwalkan; satu replika |
| Aksesibilitas | `Semantics` di 65 berkas, teks besar ditangani khusus di 7 berkas dan diuji di beberapa alur; **0** pengumuman `SemanticsService` untuk pembaruan langsung; TalkBack belum pernah diuji |
| Privasi | consent per tujuan (H/S/A/komunitas/model/analitik), ekspor JSON lengkap, hapus akun cascade; tujuan `product_analytics` **tidak dipakai kode mana pun** |

## 2. Bukti eksternal yang dipakai

Hanya sumber yang ditemukan dan dibaca abstrak/ringkasannya dalam audit ini. Angka dikutip apa adanya; tidak ada yang diekstrapolasi.

| Kode | Sumber | Temuan yang relevan |
|---|---|---|
| E1 | ADA *Standards of Care in Diabetes—2026*, Seksi 7 (doi:10.2337/dc26-S007) dan Seksi 5; ringkasan di [diabetesonthenet](https://diabetesonthenet.com/diabetes-primary-care/factsheet-2026-ada-standards), [Patient Care](https://www.patientcareonline.com/view/ada-publishes-2026-standards-of-care-with-updates-to-sections-on-technology-obesity-cardiometabolic-disease-management) | Pertimbangan dini perangkat (termasuk CGM) untuk T2D lintas rejimen; DSMES lewat telehealth/digital direkomendasikan; aplikasi, coaching digital, dan SMS disebut sebagai mode penyampaian yang efektif |
| E2 | Kemenkes, PNPK Tatalaksana DM Tipe 2 Dewasa, KMK HK.01.07/MENKES/302/2026 (17 Apr 2026), merujuk Konsensus PERKENI 2024 ([ulasan](https://legawa.com/2026/09/19/hampir-tiga-dari-empat-belum-terdiagnosis-membaca-pedoman-nasional-terbaru-diabetes-tipe-2-dewasa/)) | Pedoman nasional baru; isi bagian edukasi/pemantauan mandiri belum diverifikasi langsung dari dokumen |
| E3 | Liu & Xia 2025, meta-analisis 43 RCT aplikasi mHealth T2D (doi:10.1177/20552076251326126) | HbA1c, GDP, TD, LDL, berat turun signifikan; BCT **problem solving** dan **reward and threat** berkaitan dengan penurunan HbA1c lebih besar; kombinasi paling sederhana yang efektif: *feedback & monitoring* + *social support* + *comparison of outcomes* |
| E4 | El-Gayar dkk. 2021, meta-analisis 21 RCT (doi:10.1016/j.jbi.2021.103839) | HbA1c −0,38% (95% CI −0,50…−0,25); BCT paling efektif: *action planning* dan *self-monitoring of outcomes* |
| E5 | Jakob dkk. 2022, tinjauan sistematis 99 studi kepatuhan aplikasi PTM (doi:10.2196/35371) | Kepatuhan rata-rata **56% (SD 24%)**; pendorong: personalisasi, pengingat push individual, desain stabil, dukungan manusia pelengkap, fitur sosial/gamifikasi |
| E6 | Dugas dkk. 2026, scoping review aplikasi penghitung kalori (doi:10.2196/64139) | Pemantauan diri turun dari 5,4 ke 1,4 hari/minggu antara minggu 4 dan 12; penghalang: entri manual, basis data terbatas; pendorong: otomatisasi, personalisasi, berbagi ke tenaga kesehatan |
| E7 | Hardeman dkk. 2019, tinjauan sistematis JITAI aktivitas fisik (doi:10.1186/s12966-019-0792-7) | Bukti efek masih campur, tidak ada studi berdaya cukup; kendala sensor dan ketepatan waktu; BCT umum: goal setting, prompts, feedback, action planning |
| E8 | Adams dkk. 2013, RCT tujuan adaptif (doi:10.1371/journal.pone.0082901) | Tujuan langkah yang **menyesuaikan naik-turun** (persentil) +1.130 langkah/hari vs tujuan statis (d = 0,74) |
| E9 | Dorsch dkk. 2025, RCT JITAI myBPmyLife n=602 (doi:10.1038/s41746-025-01844-3) | Langkah dan natrium membaik, tekanan darah tidak; peringatan bahwa perubahan perilaku ≠ hasil klinis |
| E10 | Okada dkk. 2026, RCT COMPASS-Libre (doi:10.1016/j.sapharm.2026.04.005) | Pada T2D tanpa insulin, bahkan **satu** sensor isCGM 14 hari + edukasi singkat meningkatkan TIR; perilaku diet membaik pada pemakaian berulang |
| E11 | Serugunda dkk. 2025, scoping review LLM untuk penyakit kronis (doi:10.2196/66905) | 62% studi melaporkan jawaban LLM tidak akurat/konsisten; rekomendasi: integrasi dengan data nyata, antarmuka sesuai budaya/usia, kerangka evaluasi |
| E12 | Jeon dkk. 2025, DTalksBot (doi:10.2196/72553) | Pertanyaan pasien: saran personal 45%, komplikasi 27%, obat 17%, kesehatan mental 5%; klinisi menilai chatbot kurang pada akurasi kontekstual dan integrasi data real-time |
| E13 | Wang dkk. 2023, XSafety (arXiv:2310.00905) | Semua LLM yang diuji lebih sering tidak aman untuk kueri **non-Inggris**; relevan karena beOkay berbahasa Indonesia |
| E14 | OWASP Top 10 for LLM Applications 2025 ([hackerone](https://www.hackerone.com/ai/owasp-top-10-llms-2025), [genai.owasp.org](https://genai.owasp.org/2024/11/17/owasp-reveals-updated-2025-top-10-risks-for-llms-new-sponsorship-program/)) | LLM01 prompt injection, excessive agency naik karena arsitektur agentik; baru: system prompt leakage, vector/embedding weaknesses |
| E15 | Yang dkk. 2026, ToolPrivBench (arXiv:2606.20023); Chen & Cong 2025, AgentGuard (arXiv:2502.09809) | Agen LLM cenderung memilih alat berhak lebih tinggi dari yang perlu; perlu uji alur kerja alat yang tidak aman secara sistematis |
| E16 | NICE Evidence Standards Framework for DHTs ([ecd7](https://nice.org.uk/corporate/ecd7/chapter/section-c-evidence-standards-tables); Unsworth dkk. 2021 doi:10.1177/20552076211018617) | Tier B = teknologi yang membantu pasien mengelola kesehatannya; 21 standar: keselamatan, keterterimaan pengguna, ketimpangan/bias, praktik data, pengawasan profesional, efektivitas, dampak biaya |
| E17 | Pham dkk. 2019 (doi:10.2196/11941); Amagai dkk. 2022 (doi:10.2196/35120) | Studi mHealth jarang mengaitkan indikator keterlibatan dengan hasil; faktor retensi: umpan balik, pengingat tepat, dukungan dalam aplikasi, kompensasi; faktor putus: kurang dukungan, masalah teknis, kegunaan rendah |
| E18 | Krisnadewi dkk. 2024 (doi:10.7324/japs.2024.194416); Zalita dkk. 2026 (doi:10.32524/jksp.v9i3.2221) | Prolanis (BPJS): edukasi kelompok, senam, SMS pengingat, kunjungan rumah; 52,7% pasien melaporkan hambatan terutama **dukungan keluarga dan waktu**; disarankan DSME berbasis keluarga |
| E19 | Putri dkk. 2022, protokol IDSM Indonesia (doi:10.1371/journal.pone.0277127); Sari 2026 (doi:10.59261/bustechno.v7i4.784) | Aplikasi T2DM Indonesia yang dirancang bersama pasien–keluarga–nakes di Puskesmas; literasi digital, infrastruktur, interoperabilitas, privasi sebagai prasyarat |
| E20 | Amouzadeh dkk. 2025, tinjauan desain ramah lansia 132 studi (doi:10.1007/s40520-025-03157-7); Wilson dkk. 2021 (doi:10.1186/s12889-021-11623-w) | Navigasi sederhana, teks dan target sentuh besar, **interaksi suara**, antarmuka toleran galat, desain partisipatif; penghalang: efikasi diri, dukungan, literasi |
| E21 | Boronat dkk. 2026, dietary EMA (doi:10.3389/fnut.2026.1927498); Sze dkk. 2025, FiberMore (doi:10.2196/78019) | Pertanyaan diet singkat bergilir harian layak dan bermakna dengan beban rendah; foto makan + LLM untuk umpan balik serat sedang diuji RCT |
| E22 | Android Health Connect data types ([docs](https://developer.android.com/health-and-fitness/health-connect/data-types)) | `BloodGlucoseRecord`, `BloodPressureRecord`, `WeightRecord`, `SleepSessionRecord`, `StepsRecord` tersedia dengan izin baca terpisah |
| E23 | SATUSEHAT Kemenkes ([kemkes.go.id](https://www.kemkes.go.id/id/begini-cara-terintegrasi-ke-satusehat-bagi-fasyankes-dan-penyedia-rekam-medis-elektronik)) | Platform interoperabilitas nasional HL7 FHIR R4; registrasi vendor lewat portal pengembang |

Yang **tidak** ditemukan dalam audit ini: teks lengkap PERKENI 2024 / PNPK 2026 tentang pemantauan glukosa mandiri; validasi aplikasi foto makanan untuk hidangan Indonesia; RCT JITAI khusus T2D yang sudah selesai (ENERGISED masih berjalan, NCT05351359).

## 3. Analisis gap — dimensi 1: UI/UX

Prinsip penilaian: beban per catatan, keterjangkauan bagi lansia dan literasi digital rendah (E18–E20), aksesibilitas, dan apakah UI memberi umpan balik yang mendorong kebiasaan (E3–E5).

| ID | Gap | Bukti di kode | Dampak | Usulan | Ukuran |
|---|---|---|---|---|---|
| U-1 | **Tidak ada jalur catat satu ketukan** dari riwayat/favorit untuk makan dan aktivitas yang berulang | form makan selalu lewat pencarian/draf; tidak ada "ulangi makan kemarin"/favorit di `quick_record` | Entri manual = penghalang utama (E6); kepatuhan turun tajam setelah minggu ke-4 | Kartu "Sering dicatat" di Beranda dan lembar Catat: 5 makan/aktivitas terakhir atau tersering, satu ketukan menyimpan dengan waktu sekarang (tetap memakai antrean offline dan idempotensi) | median waktu per catatan (klien, lokal) turun; proporsi catatan via jalur cepat |
| U-2 | **Tidak ada input suara** | `pubspec.yaml` tanpa `speech_to_text`; parser kalimat makan sudah ada (`meal-text.parser.ts`) | Interaksi suara adalah elemen desain ramah lansia yang berulang muncul (E20) | Tombol mikrofon di Asisten dan form makan → teks → parser yang sudah ada; dikte di perangkat (Android SpeechRecognizer), tanpa mengirim audio ke server | pemakaian jalur suara; tingkat koreksi draf |
| U-3 | **TalkBack belum pernah diuji; tidak ada pengumuman perubahan langsung** | 0 pemanggilan `SemanticsService`; banner realtime, status sinkron, dan lencana hanya visual | Pengguna pembaca layar tidak tahu ada notifikasi/sinkron gagal | Tambah `SemanticsService.announce` pada banner, status antrean offline, dan hasil simpan; uji TalkBack manual pada 6 alur inti; tambah `MediaQuery.boldText`/`highContrast` ke tema | checklist TalkBack lulus; 0 overflow pada 2× (sudah diuji sebagian) |
| U-4 | **Onboarding menuntut verifikasi email sebelum apa pun** dan consent panjang | `autoSignIn: false`; state onboarding 7 langkah | Literasi digital rendah dan email jarang dipakai di segmen lansia Indonesia (E18–E19) | Mode "coba dulu": catat lokal tanpa akun selama 7 hari, lalu ajak membuat akun dan memindahkan data (antrean offline sudah per akun); consent berlapis: minimum di awal, lanjutan saat fitur dibuka (sudah per tujuan, tinggal urutannya) | konversi onboarding → catatan pertama < 5 menit |
| U-5 | **Umpan balik hasil belum "terlihat" di saat mencatat** | setelah simpan glukosa/makan, tidak ada perbandingan instan dengan median pribadi atau catatan terakhir | *Self-monitoring of outcomes* dan *feedback* adalah BCT terkuat (E3–E4) | Setelah simpan: satu baris konteks dari `stats-v1` ("lebih rendah dari median puasa 14 harimu: 128") dengan bahasa netral dan cakupan; tanpa penilaian | pengguna melihat konteks ≥ 1×/hari; survei keterbacaan |
| U-6 | **Pasangan glukosa sebelum/sesudah makan tidak dihubungkan ke makan tertentu** | `meal_context` ada di glukosa; tidak ada tampilan "respons terhadap makan ini" | Pengguna belajar dari respons per makan (E10: isCGM singkat pun mengubah perilaku diet) | Di detail makan: tampilkan pembacaan glukosa ±2 jam bila ada, sebagai pasangan, dengan kalimat "dua angka, bukan sebab-akibat" | proporsi makan yang punya pasangan; retensi |
| U-7 | **Satu bahasa, satu register** | `supportedLocales: [id_ID]`; teks ramah tetapi panjang | Pedoman lansia: kalimat pendek, satu tindakan per layar | Mode "ringkas" (kalimat ≤ 12 kata, ikon + label) sebagai preferensi, bukan bahasa baru; tunda bahasa daerah | SUS ≥ 68 pada pilot |
| U-8 | **Tidak ada widget layar utama / aksi cepat dari notifikasi** | notifikasi membuka layar; tidak ada aksi "sudah minum" langsung | Konfirmasi obat butuh 3 ketukan | Notification actions Android ("Sudah", "Nanti") untuk pengingat obat dan check-in; widget 1×1 "Catat" | konfirmasi obat via aksi notifikasi |
| U-9 | **QA visual hanya emulator dan satu ponsel; tidak ada data pengguna** | laporan fase memakai tangkapan emulator | Keterterimaan pengguna adalah standar NICE ESF 1–6 (E16) | Jalankan 5 sesi think-aloud pada draf pilot sebelum etik (sesi kegunaan tanpa data kesehatan asli tidak memerlukan persetujuan etik yang sama; pastikan dengan komite) | SUS, penyelesaian tugas |

## 4. Analisis gap — dimensi 2: Sistem

| ID | Gap | Bukti di kode | Dampak | Usulan | Ukuran |
|---|---|---|---|---|---|
| S-1 | **Tidak ada metrik, jejak, atau alarm**; hanya log JSON | 24 pemanggilan `logEvent`; tidak ada `/metrics`; runbook §5 | Tidak bisa tahu API lambat, outbox macet, push gagal, atau LLM timeout sebelum pengguna mengeluh | Endpoint `/metrics` (format Prometheus, tanpa dependensi besar: hitung sendiri) untuk latensi per rute, status outbox, antrean notifikasi, gagal LLM/Modal; alarm sederhana lewat cron + email SMTP yang sudah ada | SLO: p95 < 800 ms, outbox DEAD = 0, push gagal < 5% |
| S-2 | **Feature flag hanya env**; mematikan Asisten/ML/komunitas perlu restart | `*_ENABLED` di `env.ts` | Saat pilot, kill-switch harus detik, bukan deploy | Tabel `feature_flags` (key, enabled, note, updated_by) dibaca dengan cache 30 dtk; UI menampilkan "fitur dimatikan sementara"; log audit perubahan | waktu matikan fitur < 1 menit |
| S-3 | **Retensi data tidak terjadwal** | `audit_events`, `agent_run_events`, `notifications` tumbuh tanpa batas | Pertumbuhan DB dan kewajiban privasi (data minimization) | Pekerja harian: hapus `agent_run_events` > 90 hari, `notifications` dibaca > 60 hari, `audit_events` > 365 hari (dapat dikonfigurasi); ekspor tetap memuat yang tersisa; dokumentasikan di kebijakan privasi | ukuran tabel stabil |
| S-4 | **Satu replika, state di memori** (WebSocket, pembatas laju, cache embedding, circuit breaker) | `realtime.ts`, `rate-window.ts`, Better Auth `memory` | Batas skala keras; restart memutus semua WebSocket dan me-reset batas login | Terima untuk pilot (≤ 100 pengguna); siapkan jalur: pembatas auth ke Postgres (tabel `rate_limits`), pub/sub WebSocket via `LISTEN/NOTIFY` Postgres bila > 1 replika | didokumentasikan sebagai batas; uji beban 100 koneksi |
| S-5 | **Sinyal perangkat sempit** | Health Connect hanya `WORKOUT` | Langkah, tidur, berat, glukosa dari glukometer BLE/aplikasi lain tersedia di Health Connect (E22) | Lihat K-1; secara sistem: tabel `device_imports` generik + idempotensi per (source, external_id) sudah ada polanya di `activity_sessions` | — |
| S-6 | **Tidak ada kunci aplikasi** | tidak ada `local_auth`; token di secure storage | Data kesehatan terbuka bila ponsel dipinjam (umum di keluarga) | Kunci biometrik/PIN opsional saat membuka aplikasi dan sebelum ekspor/hapus | opt-in rate |
| S-7 | **Ekspor hanya JSON** | `export.routes.ts` content-type JSON | Tidak terbaca klinisi/keluarga; NICE "data practices" dan portabilitas | Ekspor ringkasan PDF 1–2 halaman (14/30/90 hari: median glukosa per konteks, hari aktif, kepatuhan obat, cakupan) di samping JSON; dibuat di klien agar server tidak menyimpan berkas | pengguna mengunduh PDF sebelum kontrol |
| S-8 | **CI belum pernah berjalan; tes E2E perangkat manual** | `.github/workflows/ci.yml` baru | Regresi UI hanya tertangkap manual | Push agar CI jalan; tambah `integration_test` Flutter untuk 3 alur (masuk, catat glukosa offline → sinkron, kotak masuk) di emulator CI | CI hijau; 3 E2E |
| S-9 | **Drift skema lama** (FK `activity_plans`/`score_events`, indeks `communities`) | `prisma migrate diff` | Migrasi masa depan rapuh | Satu migrasi "reconcile" yang menyamakan skema dengan DB | `migrate diff` hanya noise yang diizinkan |
| S-10 | **Keamanan belum diuji dari luar** | tidak ada pentest/ZAP/schemathesis; header keamanan di belakang proxy tak terdefinisi | Standar NICE keselamatan dan praktik data | Jalankan `security_run_zap`/`schemathesis` pada stack uji; tetapkan header (HSTS, CSP untuk halaman auth) di contoh konfigurasi proxy; uji IDOR otomatis untuk setiap rute `/:id` | 0 temuan tinggi |

## 5. Analisis gap — dimensi 3: Kapabilitas

| ID | Gap | Bukti di kode | Dampak | Usulan | Ukuran |
|---|---|---|---|---|---|
| K-1 | **Impor Health Connect hanya latihan**; tidak ada langkah harian, tidur, berat, glukosa perangkat | `device_activity_source.dart` `_types = [WORKOUT]` | Langkah harian adalah ukuran aktivitas paling murah dan paling banyak dipakai JITAI (E7–E8); glukometer BLE menulis ke Health Connect | Tambah `StepsRecord` (agregat harian), `WeightRecord`, `BloodGlucoseRecord`, `SleepSessionRecord` dengan izin terpisah dan consent per jenis; sumber jujur (`health_connect`), kualitas `device_reported`; langkah memberi makan tujuan dan JITAI | proporsi pengguna dengan ≥ 1 sumber perangkat |
| K-2 | **Tidak ada jangkar klinis**: berat, tinggi, lingkar pinggang, tekanan darah, HbA1c, hipoglikemia | `health_profiles` 4 kolom klinis; tidak ada tabel lab/vital | Tanpa ini tidak ada ukuran hasil (E3 menunjukkan berat, TD, LDL ikut membaik); PNPK/ADA memantau HbA1c tiap 3–6 bulan | Tabel `vital_measurements` (jenis, nilai, satuan, waktu, sumber) dan `lab_results` (HbA1c, lipid, kreatinin; tanggal; sumber: lab/manual/foto); UI "Hasil lab" sederhana + pengingat 3 bulan; **tanpa interpretasi klinis**, hanya tren deskriptif | ≥ 1 HbA1c tercatat per pengguna pilot |
| K-3 | **CGM/isCGM tidak didukung** | tidak ada parser CSV LibreView/Clarity, tidak ada baca `BloodGlucoseRecord` | ADA 2026 memperluas CGM ke T2D (E1); satu sensor 14 hari pun mengubah perilaku (E10) | Impor CSV LibreView (14 hari) → tabel `cgm_readings` terpisah dari `glucose_observations`; metrik TIR/TAR/TBR deskriptif dengan batasan; **tidak** memberi saran dosis | — |
| K-4 | **Tidak ada edukasi terstruktur (DSMES)** | tidak ada modul konten; Asisten hanya menjawab data | ADA 2026 merekomendasikan DSMES digital (E1); "credible source" BCT paling sering dipakai (E3); pertanyaan pasien terbanyak: komplikasi dan obat (E12) yang justru diblokir Asisten | 8–12 modul pendek berbahasa Indonesia (karbohidrat, label, hipoglikemia, kaki, sakit, puasa Ramadan, obat: *kapan bertanya ke dokter*), ditulis dan **ditinjau klinisi**, versi tercatat; Asisten merujuk modul alih-alih menolak kosong (`SAFETY` → tautan modul yang relevan) | modul dibuka; rasio jawaban "di luar yang bisa kubantu" turun |
| K-5 | **Tujuan statis; coaching hanya menurunkan** | fase 5: penyesuaian hanya ke bawah | Tujuan adaptif naik-turun lebih efektif dari statis (E8) | Tujuan langkah/aktivitas adaptif persentil (target = persentil ke-60 dari 10 hari terakhir, dibatasi ±10%/minggu), selalu bisa ditolak pengguna; log setiap perubahan (sudah ada pola `coaching_events`) | laju pencapaian 60–80% |
| K-6 | **Tidak ada BCT problem solving** | refleksi mingguan: suasana, hambatan, slot; tidak ada rencana mengatasi hambatan | *Problem solving* berkaitan dengan penurunan HbA1c lebih besar (E3) | Setelah hambatan dipilih ("waktu", "lelah", "biaya"), tawarkan 2–3 strategi dari daftar tetap yang ditinjau klinisi, pilih satu → menjadi rencana kecil; tinjau minggu depan | rencana dari problem solving yang terlaksana |
| K-7 | **Basis makanan Indonesia tipis** | TKPI bahan; "nasi goreng", "lontong", "sambal" tidak ada | Basis data terbatas = penghalang kepatuhan (E6) | Kurasi 150 hidangan Indonesia tersering (resep standar → komposisi dari TKPI, dengan rentang porsi) sebagai `food_reference` berstatus `curated`; sumber dan metode tercatat; bukan dari LLM | hit rate pencarian 20 kueri teratas |
| K-8 | **Tidak ada berbagi ke keluarga/pendamping** | tidak ada model akses tamu | Dukungan keluarga adalah hambatan utama Prolanis (E18); DSME berbasis keluarga disarankan | "Pendamping": tautan baca-saja terbatas (ringkasan mingguan + pengingat terlewat), consent terpisah, dapat dicabut, tanpa akses catatan mentah | pengguna dengan pendamping aktif |
| K-9 | **Tidak ada laporan untuk tenaga kesehatan / tautan Prolanis** | ekspor JSON saja (S-7) | Berbagi ke nakes adalah faktor keterterimaan (E6); kontrol Prolanis bulanan | PDF ringkasan (S-7) + kode QR ke tampilan baca-saja berbatas waktu; nanti FHIR `Observation` ke SATUSEHAT (E23) bila ada jalur vendor | PDF dibawa ke kontrol |
| K-10 | **Keselamatan hanya di Asisten** | nilai ekstrem di form glukosa tidak memberi pesan | Paket klinisi butir 7 | Pesan ambang (sama dengan `GLUCOSE_LIMITS`) saat menyimpan nilai ekstrem, teks ditinjau klinisi | — |
| K-11 | **Komunitas tanpa moderasi/lapor** | tidak ada tabel laporan | P3-09; risiko penyalahgunaan alias | Tombol lapor alias → antrean tinjau pemilik; sembunyikan otomatis setelah 3 laporan unik; batas laju aksi komunitas | — |

## 6. Analisis gap — dimensi 4: Hibrida agentik

Yang sudah benar dan harus dipertahankan: keselamatan deterministik sebelum LLM, alat deny-by-default dengan anggaran dan audit, saran ≠ catatan, persetujuan tepat-sekali, gerbang teks LLM tanpa angka baru. Gap-nya adalah **kecerdasan dan pembelajaran**, bukan keamanan.

| ID | Gap | Bukti di kode | Dampak | Usulan | Ukuran |
|---|---|---|---|---|---|
| A-1 | **Pemahaman maksud hanya regex** | `router-v3` + `UNKNOWN` → "Aku belum paham" | Parafrase alami jatuh; pertanyaan terbanyak pasien (saran personal, komplikasi, obat — E12) tidak terjawab atau diblokir | **Hibrida terkendali**: bila regex `UNKNOWN`, panggil LLM sebagai *pengklasifikasi* dengan keluaran terbatas (enum rute + argumen terstruktur, JSON schema), **lalu** keputusan tetap divalidasi oleh aturan yang sama (keselamatan, consent, alat yang diizinkan). LLM tidak pernah memilih alat langsung; ia mengusulkan rute. Log setiap usulan dan apakah diterima (bisa diaudit) | rasio `UNKNOWN` turun dari baseline; 0 pelanggaran gerbang |
| A-2 | **Tidak ada evaluasi kualitas agen** | tidak ada korpus percakapan beranotasi, tidak ada metrik task success | 62% studi LLM kronis melaporkan ketidakakuratan (E11); tanpa harness tidak terlihat | `tests/fixtures/conversation-corpus.ts`: 150 pesan nyata-sintetis beranotasi rute+argumen; uji regresi router (seperti korpus keselamatan); untuk teks LLM: skor otomatis *grounded* (semua angka ada di fakta) dan *safe*; laporan per versi | task-success router ≥ 90% pada korpus; grounded 100% |
| A-3 | **JITAI tidak mengukur efek dan tidak bisa belajar** | 5 pemicu; keputusan termasuk `NO_INTERVENTION` sudah disimpan di `intervention_decisions`; tanggapan dicatat; **tidak ada** hasil proksimal (apa yang terjadi 2 jam setelah pesan) dan tidak ada randomisasi | Tanpa hasil proksimal tidak ada cara tahu kapan intervensi membantu (E7, E9); P3-06 | Hitung hasil proksimal per keputusan (catatan/aktivitas dalam 2 jam, dibandingkan dengan keputusan `NO_INTERVENTION` pada konteks serupa) sebagai pekerja harian; mikro-randomisasi **opsional dan ber-consent riset** (sebagian jatah ditahan acak) hanya di pilot dengan etik | efek proksimal per pemicu |
| A-4 | **Memori sempit dan berbasis pola** | 5 jenis (`ACTIVITY_TIME`, `SCHEDULE`, `AVAILABLE_MINUTES`, `ACTIVITY_LIKE/DISLIKE`) | Personalisasi makanan/hambatan/konteks keluarga tidak tersimpan; "integrasi data real-time" adalah keluhan klinisi (E12) | Tambah jenis: `FOOD_CONTEXT` (siapa yang memasak, makan di luar), `BARRIER`, `HEALTH_EVENT` (sakit, puasa); ekstraksi LLM dengan skema ketat → **selalu** diusulkan ke pengguna sebelum disimpan (pola fase 4 sudah begitu); kedaluwarsa per jenis | memori per pengguna; penolakan usulan |
| A-5 | **Tidak ada memori episodik hasil saran** | fase 4 batasan | Agen menawarkan ulang yang pernah ditolak kecuali lewat penalti token | Ringkasan episodik per minggu ("2 dari 3 rencana jalan pagi terlaksana; sore ditolak") sebagai konteks router dan teks | pengulangan saran yang ditolak turun |
| A-6 | **Keselamatan satu lapis regex untuk bahasa Indonesia** | `safety-policy-v2` | LLM lebih sering tidak aman pada bahasa non-Inggris (E13) — saat A-1 masuk, risiko naik | Lapis kedua: LLM-as-judge **hanya untuk menahan** (tidak pernah membuka yang diblokir regex), dengan korpus adversarial yang sama + 100 kalimat injeksi prompt; versi kebijakan tetap deterministik untuk keputusan akhir | tidak ada regresi korpus; tangkapan tambahan dicatat |
| A-7 | **Ancaman agentik belum dipetakan** | tidak ada dokumen threat model OWASP LLM 2025 | Excessive agency dan prompt injection lewat konten web (`search_web_nutrition`) (E14–E15) | Threat model singkat per alat: input tak tepercaya (markdown web, OCR, nama produk OFF) hanya masuk parser deterministik, tidak pernah ke prompt tanpa pembatas; uji injeksi pada `parseNutritionPer100g` dan ekstraksi memori; hak alat minimum per rute | dokumen + 20 uji injeksi |
| A-8 | **Model hidangan tidak relevan untuk Indonesia** | 13 kelas termasuk pizza/burger/fries, `RESEARCH_ONLY`, lisensi dataset tidak jelas | Tidak bisa dipakai ke pengguna | Ganti strategi: pakai LLM visi (sudah ada) untuk *nama* + kurasi K-7 untuk *gizi*; model sendiri hanya bila ada dataset foto Indonesia berlisensi; `DEPRECATED` model lama | — |
| A-9 | **Penjelasan "mengapa" belum memakai statistik pengguna** | `FOLLOW_UP_WHY` memakai state run | Penjelasan ber-dasar data meningkatkan kepercayaan (E11) | "Mengapa" merujuk `stats-v1` (mis. "kamu 4 hari aktif pekan ini, rencana ini 15 menit = 60% sesi terpendekmu") lewat template, bukan LLM | — |

## 7. Analisis gap — dimensi 5: Dampak

| ID | Gap | Bukti di kode | Dampak | Usulan | Ukuran |
|---|---|---|---|---|---|
| D-1 | **Tidak ada analitik keterlibatan** | consent `product_analytics` tidak dibaca kode | Tidak bisa melaporkan reach/adoption/retention; studi mHealth jarang menghubungkan keterlibatan ↔ hasil (E17) | Tabel `usage_events` **berbasis consent analitik**, hanya jenis peristiwa + waktu + versi (tanpa isi kesehatan): catatan dibuat per domain, layar dibuka, saran ditawarkan/diterima, notifikasi dibuka; agregasi harian per pengguna; ikut diekspor dan dihapus bersama akun | DAU/WAU, hari-catat/minggu, retensi minggu 4 |
| D-2 | **Tidak ada ukuran hasil** | K-2 | Tanpa HbA1c/berat/TD, bahkan analisis deskriptif pra-pasca tidak mungkin | K-2 + ekspor peserta (protokol pilot) | — |
| D-3 | **Tidak ada kerangka evaluasi yang dinyatakan** | protokol pilot draf memakai SUS; tidak ada RE-AIM/NICE ESF | Pembicaraan dengan Puskesmas/BPJS/etik butuh bahasa standar | Nyatakan target **NICE ESF Tier B** dan laporkan 21 standar: sudah/belum (keselamatan ✔, praktik data ✔, keterterimaan ✘, efektivitas ✘, ketimpangan ✘, pengawasan profesional ✘) | tabel kepatuhan ESF |
| D-4 | **Ketimpangan tidak dipertimbangkan** | satu bahasa, perangkat kelas rendah belum diprofil, kuota data | NICE standar ketimpangan/bias; literasi digital lansia (E20) | Uji pada perangkat 2 GB RAM/Android 10; ukur konsumsi data per hari; mode hemat (tanpa animasi Spark, gambar dikompresi); laporkan profil peserta pilot | kinerja pada perangkat rendah |
| D-5 | **Kanal kejadian tidak diinginkan tidak ada** | laporan hanya lewat luar aplikasi | Pemantauan keselamatan pilot | Tombol "Laporkan masalah/kejadian" di Pengaturan → email ke pemilik + baris `audit_events`; tanpa data kesehatan kecuali pengguna menulisnya | laporan per 100 pengguna-minggu |
| D-6 | **Nilai bagi sistem kesehatan belum ada** | tidak ada Prolanis/SATUSEHAT/laporan nakes | Dampak di luar individu nol; Prolanis sudah punya SMS pengingat dan senam (E18) — beOkay bisa melengkapi, bukan menyaingi | K-8, K-9; jajaki satu Puskesmas sebagai mitra pilot | 1 faskes mitra |
| D-7 | **Klaim di konten harus tetap sempit** | sudah benar di kode | E9: perilaku membaik ≠ hasil klinis | Pertahankan: tidak ada klaim HbA1c di toko aplikasi/materi; laporan pilot hanya kegunaan dan beban | — |

## 8. Prioritas dan usulan fase

Matriks dampak × usaha (usaha: K = ≤ 3 hari, S = ≤ 1 minggu, B = > 1 minggu, satu pengembang):

| Prioritas | Item | Usaha | Alasan urutan |
|---|---|---|---|
| 1 | D-1 analitik ber-consent, D-5 kanal kejadian | S | Tanpa ini pilot tidak menghasilkan data; prasyarat semua ukuran lain |
| 1 | K-2 jangkar klinis (berat, TD, HbA1c) | S | Ukuran hasil; tabel sederhana, tanpa interpretasi |
| 1 | U-1 catat cepat, U-5 umpan balik saat simpan, U-6 pasangan glukosa–makan | S | Beban dan BCT terkuat; semua di atas data yang ada |
| 1 | K-5 tujuan adaptif, K-6 problem solving | S | Bukti E3/E8 langsung; memakai coaching yang ada |
| 2 | K-1 Health Connect langkah/berat/glukosa/tidur | S | Membuka JITAI berbasis langkah dan glukometer |
| 2 | S-1 metrik, S-2 feature flag, S-3 retensi, S-6 kunci aplikasi | S | Operasional pilot |
| 2 | A-2 harness evaluasi router + korpus | S | Harus ada **sebelum** A-1 |
| 2 | U-3 TalkBack, U-8 aksi notifikasi, S-7/K-9 PDF ringkasan | S | Aksesibilitas dan nilai ke nakes |
| 3 | A-1 pengklasifikasi LLM terkendali, A-6 lapis judge, A-7 threat model | B | Baru setelah harness dan korpus injeksi ada |
| 3 | K-4 modul edukasi (butuh klinisi), K-7 kurasi hidangan | B | Konten; bergantung peninjau |
| 3 | A-3 paparan JITAI (+ mikro-randomisasi hanya dengan etik), A-4/A-5 memori | B | Pembelajaran jangka panjang |
| 4 | K-3 CGM CSV, K-8 pendamping, K-11 moderasi, D-6 SATUSEHAT, U-2 suara, U-4 coba-dulu | B | Perluasan; sebagian butuh mitra |

Usulan definisi fase (masing-masing diakhiri laporan + desain FigCraft bila ada UI baru):

- **Fase 8 — Ukur dan ringankan**: D-1, D-5, K-2, U-1, U-5, U-6, K-5, K-6, K-10, S-2, S-3. Kriteria terima: setiap peristiwa pemakaian tercatat hanya dengan consent; catat-ulang satu ketukan dari Beranda; nilai ekstrem di form memberi pesan; tujuan menyesuaikan dua arah dengan log; semua ukuran §3–§7 yang ditandai "ukuran" bisa dihitung dari DB.
- **Fase 9 — Sinyal perangkat dan operasi**: K-1, S-1, S-6, S-7/K-9, U-3, U-8, S-8 (E2E), S-10. Kriteria: langkah harian dari Health Connect masuk tujuan dan JITAI; PDF ringkasan; TalkBack lulus 6 alur; CI hijau dengan E2E.
- **Fase 10 — Hibrida agentik v2**: A-2 → A-7, A-1, A-6, A-4, A-5, A-9, A-8 (deprecate). Kriteria: `UNKNOWN` turun ≥ 50% pada korpus tanpa satu pun pelanggaran gerbang; semua usulan LLM tercatat dan tervalidasi aturan; threat model + 20 uji injeksi.
- **Fase 11 — Ekosistem**: K-4 (dengan klinisi), K-7, K-8, K-3, K-11, D-6, U-2, U-4. Bergantung pada mitra (klinisi, faskes, etik).

Pemblokir yang tetap di tangan pemilik (tidak berubah dari Fase 7): kunci rilis, Firebase, tinjauan klinisi keselamatan v2, etik pilot, tinjauan hukum consent.

## 9. Yang sengaja tidak diusulkan

- **Prediksi glukosa atau saran dosis** (termasuk model seperti data assimilation): di luar batas produk dan regulasi; tetap "tidak ada prediksi" di kode.
- **LLM memilih alat secara langsung / agen multi-langkah otonom**: bukti excessive agency dan over-privileged tool selection (E14–E15); hibrida terkendali (A-1) cukup untuk kebutuhan pengguna yang terukur (E12).
- **Gamifikasi berbasis nilai glukosa/berat**: tetap hanya usaha; "reward and threat" (E3) diterjemahkan sebagai pengakuan usaha, bukan hukuman.
- **Klaim pencegahan komplikasi atau penurunan HbA1c** di materi apa pun sebelum ada studi dengan pembanding.
- **Bahasa kedua** sebelum bahasa Indonesia sendiri diuji pada lansia (U-7 dulu).

## 10. Batas audit

Tinjauan statis + hasil uji otomatis + literatur. Bukan uji penetrasi, bukan penilaian klinis, bukan tinjauan hukum, bukan uji pengguna. Angka literatur dikutip dari abstrak; dua pedoman (ADA 2026 Seksi 7, PNPK 2026) tidak dibaca teks penuhnya. Pencarian web umum (DuckDuckGo/Bing/Startpage lewat MCP) gagal dalam sesi ini; sumber web berasal dari pencarian cadangan dan basis data akademik (PubMed, OpenAlex, Europe PMC, arXiv).
