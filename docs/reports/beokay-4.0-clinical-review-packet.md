# beOkay 4.0 — Paket tinjauan klinis dan hukum

Status semua butir di bawah: **REQUIRES_CLINICAL_REVIEW** (atau tinjauan hukum untuk consent). Di produksi (`EDUCATION_INCLUDE_DRAFTS=false`) konten draf tidak disajikan; asisten abstain.

## A. Konten pencegahan (baru, draf)

| Kunci | Judul | Jalur | Yang perlu dinilai |
|---|---|---|---|
| `cegah-diabetes` | Mencegah atau menunda diabetes tipe 2 | PREVENTION | Ketepatan definisi prediabetes, kebiasaan yang dianjurkan, kalimat "beOkay tidak memberi target berat badan" |
| `pemeriksaan-rutin` | Pemeriksaan rutin | PREVENTION, WELLNESS | Daftar keluhan yang menyarankan periksa; kalimat bahwa jadwal ditentukan nakes |
| `tidur-dan-pulih` | Tidur dan pemulihan | semua jalur | Angka "7 jam atau lebih" (konsensus AASM/SRS 2015), kalimat batas akurasi perangkat, kapan merujuk |

Sumber yang dikutip: ADA Standards of Care 2026 (bagian Prevention or Delay of Diabetes), WHO Guidelines on physical activity and sedentary behaviour 2020, Watson dkk. Sleep 2015. Teks adalah ringkasan tim, bukan kutipan; perlu dicek terhadap sumber.

## B. Pemetaan jalur konten

Untuk ditinjau apakah pemetaannya benar (`server/src/content/education/modules.ts` → `MODULE_JOURNEYS`, `server/src/features/coaching/coaching.strategies.ts` → `STRATEGY_JOURNEYS`):

- Hanya T2DM/pencatatan saja: `mengenal-dmt2`, `hipoglikemia`, `perawatan-kaki`, `saat-sakit`, `puasa-ramadan`, `obat-bertanya-dokter`, `cek-gula-mandiri`, strategi `FORGOT_VISIBLE`.
- Semua jalur: `karbohidrat-porsi`, `label-gizi`, `aktivitas-aman`, `tidur-dan-pulih`, strategi lain.

## C. Teks yang dihasilkan aturan

| Tempat | Teks |
|---|---|
| `sleep.recovery` | "Angka ini perkiraan perangkat, bukan penilaian kesehatan."; rujukan bila mendengkur keras / kantuk berat |
| `prevention.education` abstain | "Aku belum punya bacaan yang cukup … Tanyakan ke tenaga kesehatanmu" |
| Penolakan jalur | "Fitur saran ini belum tersedia untuk keadaanmu …" (untuk tipe 1, di bawah 18, usia tidak diketahui) |
| Langkah berikutnya | "Utamakan keselamatanmu … Saran kebiasaan ditunda dulu." |
| Strategi | 14 strategi `strategy-catalog-v1` (masih `DRAFT_NOT_CLINICALLY_REVIEWED`) |

## D. Keputusan kebijakan yang butuh konfirmasi klinis

1. Pernyataan "pernah diberi tahu nakes prediabetes/berisiko" cukup untuk jalur pencegahan, tanpa bukti (Q2).
2. Tipe 1, usia < 18, atau usia tidak diketahui = pencatatan saja (Q3).
3. JITAI v3 menahan pengingat proaktif bila ada balasan keselamatan dalam 24 jam atau ingatan "sedang sakit" aktif.
4. `score-v2`: tidak ada intensitas, glukosa, berat, kalori, atau diagnosis sebagai variabel peringkat.

## E. Tinjauan hukum

Teks consent 1.1 (`server/src/features/consent/consent.policy.ts`), termasuk dua tujuan baru `device_data_coaching` dan `social_outcomes_memory`.

## Cara menandai tertinjau

Modul edukasi: `educationService.review(key, version, reviewer)` (sudah ada); `knowledgeService.sync()` lalu mengikuti status itu untuk jalur A. Strategi dan teks aturan: perubahan kode + versi baru.
