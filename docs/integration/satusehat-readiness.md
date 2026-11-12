# Kesiapan FHIR R4 dan SATUSEHAT (3.0 Fase 11, D-6)

Status: **belum tersambung ke SATUSEHAT.** beOkay menyediakan ekspor FHIR R4 yang bisa dibawa sendiri oleh pengguna (`GET /api/me/export/fhir`, tombol "Ekspor FHIR R4" di Pengaturan → Privasi & data → Data saya). Dokumen ini mencatat apa yang sudah sesuai dan apa yang masih kurang untuk integrasi resmi.

## Yang sudah ada

| Aspek | Keadaan |
|---|---|
| Format | `Bundle` bertipe `collection`, FHIR R4, `application/fhir+json`, versi ekspor `beokay-fhir-r4-v1` di `meta.tag` |
| Pasien | satu `Patient` dengan `id` = id akun beOkay dan nama tampilan; tanpa NIK, tanggal lahir, atau alamat |
| Pengukuran | `Observation` berstatus `final`, `subject` dan `performer` = pasien (diukur sendiri), satuan UCUM |
| Kode | LOINC: glukosa kapiler glukometer 41653-7 (mg/dL), HbA1c 4548-4 / 59261-8 (IFCC), glukosa puasa lab 1558-6 / 14771-0, LDL 2089-1 / 22748-8, HDL 2085-9 / 14646-4, kolesterol total 2093-3 / 14647-2, trigliserida 2571-8 / 14927-8, kreatinin 2160-0 / 14682-9, ACR urin 9318-7 (mg/g), berat 29463-7, tinggi 8302-2, panel tekanan darah 85354-9 (sistolik 8480-6, diastolik 8462-4), langkah 24 jam 41950-7 |
| Tanpa kode | eGFR, ACR dalam mg/mmol, dan lingkar pinggang hanya memakai `code.text` karena metode/kode LOINC yang tepat belum dipastikan |
| Konteks makan | glukosa membawa `note` "Konteks: puasa/sebelum makan/…" |
| Tidak diekspor | bacaan CGM (belum ada pemetaan yang disepakati), makanan, aktivitas sesi, obat (perlu `MedicationStatement` dan kode KFA) |

Uji: `server/tests/unit/phase11.test.ts` (struktur Bundle, kode LOINC, komponen tekanan darah) dan `server/tests/integration/phase11.test.ts` (ekspor hanya berisi data pemilik, tercatat di audit). Belum divalidasi dengan validator FHIR resmi (HL7 validator) atau profil SATUSEHAT.

## Yang masih kurang untuk SATUSEHAT

1. **Registrasi**: SATUSEHAT melayani fasilitas kesehatan dan penyedia rekam medis elektronik yang terdaftar lewat portal pengembang Kemenkes (lingkungan sandbox lalu produksi, kredensial OAuth2 client credentials per organisasi). beOkay adalah aplikasi milik pasien, bukan faskes; jalur yang realistis adalah lewat faskes mitra (mis. Puskesmas pilot) yang mengirim data ke SATUSEHAT.
2. **Identitas pasien**: SATUSEHAT memakai ID pasien (IHS number) yang dicari lewat NIK. beOkay sengaja tidak menyimpan NIK. Integrasi butuh persetujuan terpisah, alasan hukum, dan penyimpanan NIK yang aman, atau pencocokan dilakukan oleh faskes.
3. **Profil Indonesia**: resource harus mengikuti profil dan terminologi SATUSEHAT (mis. `Organization`, `Encounter` dari faskes, kode KFA untuk obat). Pengukuran mandiri pasien belum tentu diterima sebagai `Observation` tanpa `Encounter`.
4. **Persetujuan**: berbagi ke sistem nasional butuh tujuan consent baru dan penjelasan yang ditinjau pihak berwenang (UU PDP).
5. **Validasi**: jalankan HL7 FHIR validator terhadap keluaran ekspor dan, bila sudah ada akses sandbox, terhadap profil SATUSEHAT.

## Langkah berikut yang disarankan (butuh mitra)

- Jajaki satu Puskesmas sebagai mitra pilot (gap analysis D-6, ukuran: 1 faskes mitra).
- Uji ekspor FHIR sebagai lampiran kunjungan kontrol bersama tautan ringkasan (Fase 9) sebelum integrasi API.
- Bila faskes bersedia, rancang alur di mana faskes mengimpor Bundle dari pasien dan mengirimnya ke SATUSEHAT dengan identitas faskes.
