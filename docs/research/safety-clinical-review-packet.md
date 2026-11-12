# Paket tinjauan klinisi — `safety-policy-v2`

> Status: **MENUNGGU TINJAUAN KLINISI.** Belum ada tenaga kesehatan yang meninjau aturan, ambang, atau pesan di dokumen ini. Paket disiapkan 11 November 2026 (beOkay 3.0 Fase 7) untuk audit F-11.
> Sumber kebenaran: `server/src/features/agent/agent.safety.ts`. Korpus uji: `server/tests/fixtures/safety-corpus.ts` (99 kalimat).

## 1. Di mana saringan berjalan

Setiap pesan bebas ke Asisten melewati `screenRequest` **sebelum** maksud pesan ditentukan dan sebelum alat apa pun dijalankan:

- Asisten percakapan (`conversation.router.ts`, `routeMessage`): langkah pertama. Bila sebuah aturan cocok, balasan hanya berisi kartu keselamatan; tidak ada saran makanan, aktivitas, atau statistik.
- Agen saran (`agent.service.ts`, `createRun`): status run menjadi `BLOCKED` dan alat tidak dijalankan. Keputusan dicatat di `agent_run_events` (`SAFETY_SCREEN`, versi kebijakan).

Saringan **tidak** berjalan pada kolom catatan di form (catatan makan, catatan glukosa), nilai glukosa yang dicatat lewat form, atau isi notifikasi. Hanya pesan ke Asisten.

## 2. Aturan, urutan, dan pesan

Aturan diperiksa berurutan; yang pertama cocok menang. "Mendesak" menampilkan kartu berjudul "Segera cari bantuan".

| # | Kode | Keputusan | Mendesak | Pemicu (ringkas) | Pesan ke pengguna |
|---|---|---|---|---|---|
| 1 | `SELF_HARM` | NEEDS_CLINICAL_REVIEW | ya | bunuh diri/"bundir", ingin mati, mending mati, capek hidup, tidak mau hidup lagi, menyakiti/melukai diri, sayat nadi, padanan Inggris | "Terima kasih sudah bercerita. Kamu tidak harus menghadapinya sendirian. Jika kamu merasa tidak aman sekarang, segera hubungi layanan gawat darurat atau minta orang terdekat menemanimu. Bicara dengan tenaga kesehatan jiwa juga bisa membantu." |
| 2 | `URGENT_SYMPTOM` | NEEDS_CLINICAL_REVIEW | ya | pingsan/semaput/kapiuhan, hilang kesadaran; nyeri/sesak/tertekan di dada; sesak napas, napas bau aseton; kejang; keringat dingin, gemetar hebat; **gugus tanda hipoglikemia** (≥ 2 dari: gemetar, keringat, berdebar, lemas, pusing, linglung, pandangan kabur/gelap, sangat lapar); tanda stroke (wajah mencong, bicara pelo, lumpuh, lemah sebelah badan); muntah terus-menerus, tidak bisa makan dan minum; "hipo", hipoglikemia, hiperglikemia, ketoasidosis; kehilangan penglihatan mendadak; overdosis, kelebihan insulin, salah suntik, keracunan | "Gejala seperti ini perlu penilaian tenaga kesehatan. Jika terasa darurat, hubungi layanan gawat darurat atau segera ke fasilitas kesehatan terdekat. Saya tidak memberi saran makanan untuk situasi ini." |
| 3 | `GLUCOSE_EXTREME` | NEEDS_CLINICAL_REVIEW | ya | angka gula darah < 70 mg/dL atau ≥ 300 mg/dL (< 3,9 atau ≥ 16,7 mmol/L) yang disebut dalam pesan; "gula darah drop/anjlok/sangat rendah/tinggi banget" | "Angka gula darah seperti ini perlu segera ditangani. Ikuti rencana penanganan dari dokter atau tenaga kesehatanmu. Jika disertai lemas berat, bingung, muntah, atau pingsan, hubungi layanan gawat darurat atau segera ke fasilitas kesehatan terdekat. Saya tidak memberi saran makanan atau obat untuk situasi ini." |
| 4 | `SYMPTOM_REVIEW` | NEEDS_CLINICAL_REVIEW | tidak | luka (kaki) tidak sembuh, bernanah, menghitam; jari/kuku kaki menghitam atau membiru; kaki bengkak/kebas; kesemutan, mati rasa; haus terus, sering kencing; pandangan kabur; demam tinggi/terus | "Keluhan seperti ini sebaiknya diperiksa tenaga kesehatan, apalagi pada diabetes. Buat janji dengan dokter atau puskesmas dalam waktu dekat. Jika memburuk dengan cepat, disertai demam tinggi, atau luka menghitam, segera ke fasilitas kesehatan. Saya tidak memberi saran makanan atau aktivitas untuk keluhan ini." |
| 5 | `INJURY_OR_PAIN` | NEEDS_CLINICAL_REVIEW | tidak | cedera, nyeri, ngilu, encok, sakit kaki/lutut/punggung/sendi/otot/kepala, pusing (termasuk mumet, ngelu, lieur, kliyengan), keseleo, patah tulang | "Jika kamu sedang cedera, nyeri, atau pusing, sebaiknya periksakan ke tenaga kesehatan dulu. Saya tidak menyarankan aktivitas dalam kondisi ini." |
| 6 | `INTENSITY_ESCALATION` | BLOCKED | tidak | tambah/naikkan intensitas, latihan sampai maksimal/kelelahan/muntah, maraton, HIIT | "Saya tidak menaikkan intensitas aktivitas. …" |
| 7 | `MEDICATION_ADVICE` | BLOCKED | tidak | dosis, ubah/ganti/stop obat atau insulin, obat dikurangi/ditambah, dosis terlewat ("lupa minum obat, boleh dobel?"), nama obat diabetes (metformin, sulfonilurea, DPP-4, SGLT2, GLP-1, insulin dengan merek umum) | "Saya tidak dapat menyarankan perubahan obat atau dosis. Bicarakan dengan dokter atau apotekermu. …" |
| 8 | `DIAGNOSIS_REQUEST` | BLOCKED | tidak | "apakah saya kena diabetes/kencing manis/sakit gula", minta diagnosis, menafsirkan HbA1c atau hasil lab | "beOkay bukan alat diagnosis. Pemeriksaan dan diagnosis dilakukan oleh tenaga kesehatan." |
| 9 | `HEALTH_CLAIM_REQUEST` | BLOCKED | tidak | makanan yang menyembuhkan/menurunkan gula darah, obat alami/herbal/jamu untuk diabetes, sembuh dari diabetes | "Saya tidak dapat menjanjikan makanan tertentu menyembuhkan atau menurunkan gula darah. …" |
| 10 | `EXTREME_RESTRICTION` | BLOCKED | tidak | puasa total/≥ 2 hari (di luar puasa Ramadan/sunnah), berniat tidak makan seharian, makan sekali sehari, ≤ 800 kkal per hari, sengaja muntah, pencahar untuk kurus | "Saya tidak menyarankan pembatasan makan yang ekstrem. …" |

Urutan sengaja menaruh keadaan darurat di depan larangan saran obat: pada v1, "aku kelebihan suntik insulin, sekarang gemetar" dijawab dengan penolakan saran obat, bukan pesan darurat. Di v2 kalimat itu menjadi `URGENT_SYMPTOM`.

## 3. Normalisasi teks sebelum dicocokkan

1. Huruf kecil, diakritik dibuang, tanda baca menjadi spasi (kecuali titik/koma di antara angka dan `/` untuk satuan).
2. Reduplikasi angka: "kejang2" → "kejang kejang".
3. Huruf berulang ≥ 3 dipadatkan: "sesaaak" → "sesak".
4. "deg-degan" → "berdebar".
5. Kamus singkatan dan ejaan: gak/ga/nggak/tdk → tidak; bgt → banget; aku/gue → saya; nafas/nfs → napas; sesek → sesak; pinsan → pingsan; klenger/kapiuhan → semaput; lemes → lemas; gemeteran → gemetar; keringet → keringat; nurunin → menurunkan; mumet/ngelu/lieur/kliyengan → pusing; metformim → metformin.
6. Akhiran milik dilepas pada kata tubuh/gejala: dadaku → dada, napasku → napas, gulaku → gula, lukanya → luka.

## 4. Pembaca angka glukosa

- Kata kepala: "gula darah", "kadar gula", "glukosa", "GD/GDS/GDP", atau "gula" yang tidak diikuti nama bahan (pasir, aren, merah, batu, jawa, …).
- Angka pertama dalam 6 kata sesudahnya dipakai, kecuali angka yang didahului jam/pukul/tanggal/naik/turun/selisih atau diikuti satuan non-glukosa (gram, sendok, kalori, hari, menit, jam, piring, …).
- Satuan: `mmol` → mmol/L; `mg`/`mg/dl` → mg/dL. Tanpa satuan: bilangan desimal < 35 atau bilangan bulat < 20 dianggap mmol/L, selain itu mg/dL (mg/dL lazim di Indonesia).
- Ambang (`GLUCOSE_LIMITS`): rendah < 70 mg/dL (3,9 mmol/L) mengikuti batas hipoglikemia tingkat 1 yang umum dipakai; tinggi ≥ 300 mg/dL (16,7 mmol/L) adalah **usulan produk**, bukan kutipan pedoman. Keduanya perlu diputuskan klinisi.

## 5. Kelemahan yang diketahui

| Jenis | Contoh | Akibat |
|---|---|---|
| Positif palsu: gugus hipo dari olahraga biasa | "habis olahraga keringatan terus lemas" | kartu darurat, padahal mungkin lelah biasa |
| Positif palsu: idiom | "keringat dingin pas presentasi" | kartu darurat |
| Positif palsu: pertanyaan istilah | "apa itu hipoglikemia?" | kartu darurat, bukan penjelasan |
| Positif palsu: negasi tidak dipahami | "saya tidak pingsan kok" | kartu darurat |
| Negatif palsu: parafrase di luar kamus | bahasa daerah lain, ejaan yang tidak ada di kamus, kalimat tanpa kata kunci ("rasanya mau ambruk") | tidak ada kartu |
| Negatif palsu: gejala tunggal yang samar | "lemas banget" saja, "berdebar" saja | tidak ada kartu (sengaja, untuk menghindari positif palsu) |
| Angka ambigu | "gula 18" (mmol atau mg/dL?) | dibaca 18 mmol/L → darurat |
| Puasa Ramadan | "aman gak puasa Ramadan dengan diabetes?" | dibiarkan lolos; tidak ada panduan khusus |
| Cakupan saluran | catatan di form, nilai glukosa di form | tidak disaring |

Regex tidak bisa menjamin cakupan. Korpus menguji 99 kalimat (71 positif, 28 harus lolos) dan setiap aturan punya minimal satu contoh positif; itu bukti regresi, bukan bukti keamanan klinis.

## 6. Pertanyaan untuk klinisi

1. Apakah ambang < 70 dan ≥ 300 mg/dL tepat untuk memicu pesan "segera ditangani"? Perlukah tingkat kedua (< 54 mg/dL) dengan pesan yang lebih tegas?
2. Untuk gula rendah, bolehkah pesan menyebut langkah pertolongan pertama yang umum (mis. karbohidrat cepat serap lalu cek ulang), atau tetap "ikuti rencana dari doktermu"?
3. Perlukah nomor darurat ditulis eksplisit (mis. 112 atau 119 di Indonesia)? Nomor mana yang benar untuk pengguna sasaran?
4. Gugus tanda hipoglikemia (≥ 2 tanda): tanda mana yang perlu ditambah atau dibuang? Apakah "pusing + lemas" layak dianggap darurat?
5. `SYMPTOM_REVIEW`: apakah luka kaki menghitam/bernanah seharusnya mendesak (kartu darurat), bukan sekadar "buat janji"?
6. Puasa Ramadan bagi penyandang T2DM: perlukah pesan khusus yang mengarahkan ke konsultasi pra-Ramadan?
7. Perlukah pesan glukosa ekstrem juga muncul saat nilai dicatat lewat form glukosa (bukan hanya di Asisten)?
8. Untuk menyakiti diri: layanan konseling mana yang boleh dirujuk?

## 6a. Tambahan 3.0 Fase 8 (perlu ditinjau bersama butir di atas)

Pertanyaan 7 sudah diimplementasikan sebagai usulan, menunggu persetujuan:

**Pesan nilai ekstrem di form dan detail glukosa** (`server/src/features/glucose/glucose.alerts.ts`, salinan teks di `app/lib/features/glucose/data/glucose_models.dart`). Ambang sama dengan `GLUCOSE_LIMITS` (< 70 dan ≥ 300 mg/dL setelah konversi; mmol/L dikali 18,016). Pesan muncul saat mengetik (sebelum simpan) dan di detail catatan; penyimpanan tidak diblokir.

| Tingkat | Judul | Pesan |
|---|---|---|
| `LOW` | Angka ini di bawah 70 mg/dL | Bila kamu merasa gemetar, berkeringat, bingung, atau lemas, ikuti rencana penanganan gula rendah dari tenaga kesehatanmu. Bila tidak membaik, pingsan, atau sulit sadar, segera hubungi layanan darurat 119. |
| `HIGH` | Angka ini 300 mg/dL atau lebih | Periksa ulang dengan alat yang sama bila memungkinkan. Bila tetap tinggi, atau disertai muntah, sangat haus, sesak, atau lemas berat, segera hubungi tenaga kesehatan atau layanan darurat 119. |

**Daftar strategi problem solving** (`server/src/features/coaching/coaching.strategies.ts`, `strategy-catalog-v1`, status `DRAFT_NOT_CLINICALLY_REVIEWED` yang ditampilkan ke pengguna sebagai "Daftar cara ini masih menunggu tinjauan tenaga kesehatan"). Setiap hambatan di refleksi mingguan punya 2–3 strategi tetap; pengguna memilih satu yang menjadi rencana 7 hari yang dikonfirmasi sendiri. Strategi tidak mengubah obat, makanan, atau intensitas aktivitas.

| Hambatan | Strategi |
|---|---|
| Waktu | Bagi jadi potongan 10 menit · Tempelkan ke kegiatan rutin · Pilih satu jam longgar tiap pagi |
| Lupa | Pasang satu pengingat · Taruh alat di tempat terlihat · Catat langsung setelah makan |
| Tenaga | Pilih versi yang ringan · Pakai jam saat paling segar · Ceritakan lelahmu ke tenaga kesehatan |
| Motivasi | Kecilkan langkahnya · Ajak satu orang · Ingat alasanmu sendiri |
| Hal lain | Fokus pada satu hal minggu ini · Bicarakan dengan tenaga kesehatan |

Pertanyaan tambahan:

9. Apakah pesan form glukosa di atas tepat, dan apakah 119 nomor yang benar?
10. Apakah ada strategi yang tidak aman untuk penyandang T2DM tertentu (mis. "versi ringan" bagi yang sedang hipoglikemia)? Perlukah strategi dikunci bila ada catatan glukosa ekstrem dalam 7 hari terakhir?
11. Laporan "Kejadian tidak diinginkan" dari aplikasi (Pengaturan → Laporkan masalah) dikirim ke surel pemilik. Siapa yang harus membaca dan dalam berapa lama selama pilot?

## 6b. Tambahan 3.0 Fase 11: modul edukasi dan hidangan terkurasi

**Modul edukasi** (`server/src/content/education/modules.ts`, 10 modul, versi 1, ditulis 12 Nov 2026 oleh pengembang, **belum ditinjau klinisi**). Produksi tidak menampilkan modul sampai pemilik menjalankan `scripts/ops/education.ts review` untuk modul yang sudah disetujui. Modul: mengenal DMT2 dan HbA1c, karbohidrat dan porsi (metode piring), membaca label gizi, hipoglikemia (ambang 70/54 mg/dL, aturan 15 gram/15 menit sebagai "yang umum diajarkan"), merawat kaki, saat sakit, puasa Ramadan (batalkan bila < 70 atau > 300 mg/dL, rujukan IDF-DAR 2021), obat: kapan bertanya ke dokter, bergerak dengan aman (150 menit/minggu), memeriksa gula darah sendiri dan CGM (TIR > 70%, TBR < 4%).

Pemetaan jawaban keselamatan Asisten → modul (`SAFETY_MODULES`): `URGENT_SYMPTOM`/`GLUCOSE_EXTREME` → hipoglikemia, saat sakit; `SYMPTOM_REVIEW` → merawat kaki, saat sakit; `MEDICATION_ADVICE` → obat; `DIAGNOSIS_REQUEST` → mengenal DMT2, memeriksa gula darah; `HEALTH_CLAIM_REQUEST` → karbohidrat, label gizi; `EXTREME_RESTRICTION` → karbohidrat, puasa Ramadan; `INJURY_OR_PAIN`/`INTENSITY_ESCALATION` → bergerak dengan aman. `SELF_HARM` tidak ditautkan ke modul.

**Hidangan terkurasi** (`server/src/content/food/curated-dishes.ts`, 45 hidangan): resep standar disusun pengembang dari bahan TKPI 2017, tanpa faktor retensi zat gizi dan susut masak; minyak terserap diperkirakan; lontong dihitung sebagai nasi. Ditandai `needs_dietitian_review` dan ditampilkan dengan label "Kurasi beOkay · dari bahan TKPI". Perlu ahli gizi.

Pertanyaan tambahan:

12. Apakah isi tiap modul akurat dan sesuai PNPK 2026/PERKENI untuk Indonesia? Apakah aturan 15 gram/15 menit dan ambang pembatalan puasa boleh ditampilkan, atau cukup "ikuti rencana dari doktermu"?
13. Apakah pemetaan kode keselamatan → modul tepat, terutama untuk gejala darurat (apakah tautan modul bisa mengalihkan perhatian dari "segera cari bantuan")?
14. (Ahli gizi) Apakah resep standar dan porsi umum 45 hidangan masuk akal untuk konteks Indonesia? Hidangan mana yang perlu faktor susut masak?

## 7. Cara memeriksa ulang

```bash
docker compose -f compose.test.yaml run --rm tester bun test tests/unit/agent-safety.test.ts tests/unit/conversation.test.ts
```

Menambah kasus cukup dengan baris baru di `tests/fixtures/safety-corpus.ts`. Mengubah aturan wajib menaikkan `SAFETY_POLICY_VERSION`; versi tersimpan di setiap rekomendasi dan peristiwa `SAFETY_SCREEN`.

## 8. Lembar persetujuan

| Peninjau | Profesi / STR | Tanggal | Keputusan | Catatan |
|---|---|---|---|---|
| | | | | |
