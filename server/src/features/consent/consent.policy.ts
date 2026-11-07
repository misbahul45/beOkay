export const CONSENT_PURPOSES = ["health_data_processing", "descriptive_summaries", "product_analytics"] as const;
export type ConsentPurpose = (typeof CONSENT_PURPOSES)[number];

export const CONSENT_SOURCES = ["onboarding", "settings", "api"] as const;
export type ConsentSource = (typeof CONSENT_SOURCES)[number];

export type PurposeDefinition = {
  purpose: ConsentPurpose;
  required: boolean;
  title: string;
  description: string;
  dataCategories: string[];
  withdrawalEffect: string;
};

export type ConsentPolicy = {
  version: string;
  effectiveDate: string;
  summary: string;
  purposes: PurposeDefinition[];
};

export const currentPolicy: ConsentPolicy = {
  version: "1.0",
  effectiveDate: "2026-11-08",
  summary:
    "beOkay hanya memproses informasi yang kamu masukkan sendiri untuk membantu kamu mencatat dan memahami kebiasaan harian. beOkay bukan alat diagnosis dan tidak memberi saran medis. Teks ini adalah draf dan wajib ditinjau pihak yang berwenang sebelum dipakai di produksi.",
  purposes: [
    {
      purpose: "health_data_processing",
      required: true,
      title: "Mencatat data kesehatan yang kamu masukkan",
      description:
        "Menyimpan profil kesehatan, makanan, aktivitas, glukosa, dan obat yang kamu catat agar bisa ditampilkan kembali kepadamu.",
      dataCategories: ["Profil kesehatan yang kamu laporkan", "Catatan harian yang kamu masukkan"],
      withdrawalEffect:
        "Fitur yang memproses data kesehatan dihentikan. Akunmu tetap bisa dibuka. Data yang sudah tersimpan tidak otomatis dihapus; kamu bisa meminta penghapusan di Privasi & data.",
    },
    {
      purpose: "descriptive_summaries",
      required: true,
      title: "Membuat ringkasan dan insight deskriptif",
      description:
        "Menghitung ringkasan harian dan mingguan dari catatanmu, tanpa prediksi dan tanpa kesimpulan sebab-akibat.",
      dataCategories: ["Ringkasan yang dihitung dari catatanmu"],
      withdrawalEffect: "Ringkasan baru tidak dibuat. Ringkasan lama tidak ditampilkan sampai kamu menyetujui kembali.",
    },
    {
      purpose: "product_analytics",
      required: false,
      title: "Membantu meningkatkan aplikasi",
      description: "Menggunakan data penggunaan yang tidak memuat isi catatan kesehatanmu untuk memperbaiki aplikasi. Opsional.",
      dataCategories: ["Data penggunaan aplikasi tanpa isi catatan kesehatan"],
      withdrawalEffect: "Data penggunaan tidak lagi dipakai untuk tujuan ini. Tidak memengaruhi fitur lain.",
    },
  ],
};

export const requiredPurposes: ConsentPurpose[] = currentPolicy.purposes.filter((p) => p.required).map((p) => p.purpose);
