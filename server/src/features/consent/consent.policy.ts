export const CONSENT_PURPOSES = ["health_data_processing", "descriptive_summaries", "product_analytics", "personalized_ai", "community_membership", "challenge_participation", "leaderboard_visibility", "model_inference", "ai_text_generation", "ai_message_understanding", "companion_sharing", "device_data_coaching", "social_outcomes_memory"] as const;
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
  version: "1.1",
  effectiveDate: "2026-11-13",
  summary:
    "beOkay memproses informasi yang kamu masukkan sendiri, dan data perangkat yang kamu izinkan, untuk membantu kamu mencatat dan menjaga kebiasaan harian: pencegahan, dukungan diabetes tipe 2, atau gaya hidup sehat. beOkay bukan alat diagnosis dan tidak memberi saran medis. Teks ini adalah draf dan wajib ditinjau pihak yang berwenang sebelum dipakai di produksi.",
  purposes: [
    {
      purpose: "health_data_processing",
      required: true,
      title: "Mencatat data kesehatan yang kamu masukkan",
      description:
        "Menyimpan profil kesehatan, jalur yang kamu pilih, serta makanan, aktivitas, tidur, dan bila kamu mencatatnya glukosa dan obat, agar bisa ditampilkan kembali kepadamu.",
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
    {
      purpose: "personalized_ai",
      required: false,
      title: "Saran personal dari asisten beOkay",
      description:
        "Memakai preferensi makananmu dan catatan yang relevan untuk menyusun pilihan makanan. Semua saran menunggu persetujuanmu, tidak mengubah catatan kesehatan, dan bukan saran medis. Teks tetap dibuat dari aturan; data tidak dikirim ke pihak ketiga untuk ini.",
      dataCategories: ["Preferensi dan alergi makananmu", "Keputusanmu atas setiap saran"],
      withdrawalEffect: "Saran baru tidak dibuat dan saran yang menunggu tidak bisa diterima. Preferensi yang sudah dipelajari tetap tersimpan sampai kamu menghapusnya.",
    },
    {
      purpose: "community_membership",
      required: false,
      title: "Bergabung dengan komunitas wilayah",
      description: "Bergabung dengan komunitas di tingkat provinsi memakai alias yang kamu pilih. Yang terlihat oleh anggota hanya aliasmu; tidak ada data kesehatan, lokasi tepat, atau namamu.",
      dataCategories: ["Wilayah (provinsi) yang kamu pilih", "Alias komunitas"],
      withdrawalEffect: "Kamu tidak dapat bergabung atau tampil di komunitas. Keanggotaan yang ada tidak ditampilkan lagi sampai kamu menyetujui kembali.",
    },
    {
      purpose: "challenge_participation",
      required: false,
      title: "Ikut tantangan kebiasaan",
      description: "Ikut tantangan hari aktif. Skor dihitung dari catatan aktivitas atau check-in yang kamu pilih sendiri, bukan dari nilai kesehatan.",
      dataCategories: ["Hari aktif dan check-in kebiasaan"],
      withdrawalEffect: "Kamu tidak dapat ikut atau memperbarui skor tantangan.",
    },
    {
      purpose: "leaderboard_visibility",
      required: false,
      title: "Tampil di papan peringkat",
      description: "Menampilkan alias dan skor kebiasaanmu di papan peringkat tantangan. Bisa dimatikan kapan saja dan berlaku segera.",
      dataCategories: ["Alias dan skor tantangan"],
      withdrawalEffect: "Aliasmu langsung hilang dari papan peringkat.",
    },
    {
      purpose: "model_inference",
      required: false,
      title: "Evaluasi model pengenal makanan",
      description: "Mengirim foto makanan yang kamu pindai ke layanan model kami (Modal) untuk mengenali nama hidangan. Selama model masih tahap uji, hasilnya hanya dievaluasi di belakang layar. Setelah model disetujui, hasilnya tampil sebagai perkiraan yang harus kamu periksa, tidak pernah dicatat otomatis. Foto tidak disimpan.",
      dataCategories: ["Foto makanan yang kamu pindai (hanya saat memindai)"],
      withdrawalEffect: "Foto tidak lagi dikirim ke layanan model. Tidak memengaruhi fitur lain.",
    },
    {
      purpose: "ai_text_generation",
      required: false,
      title: "Teks saran ditulis model bahasa",
      description: "Menyusun penjelasan saran dengan bantuan model bahasa pihak ketiga (Mistral). Yang dikirim hanya fakta saran itu: nama makanan atau aktivitas, nilai gizi bersumber, alasan peringkat, dan kata pencarianmu. Tidak dikirim: nama, surel, alergi, kadar glukosa, atau riwayat catatanmu. Teks selalu diperiksa aturan keselamatan dan diganti templat bila gagal.",
      dataCategories: ["Fakta saran (nama makanan/aktivitas, nilai gizi bersumber, kata pencarian)"],
      withdrawalEffect: "Penjelasan kembali memakai templat tetap. Saran yang sudah ada tidak berubah.",
    },
    {
      purpose: "ai_message_understanding",
      required: false,
      title: "Memahami pesan dengan model bahasa",
      description: "Bila aturan beOkay tidak mengenali pesanmu di Asisten, teks pesan itu dikirim ke model bahasa pihak ketiga (Mistral) untuk menebak jenis bantuan yang kamu maksud dan memeriksa keamanannya. Model hanya mengusulkan; aturan keselamatan dan persetujuanmu yang memutuskan. Nama, surel, dan catatan kesehatanmu tidak dikirim.",
      dataCategories: ["Teks pesan Asisten yang tidak dikenali aturan"],
      withdrawalEffect: "Pesan yang tidak dikenali dijawab dengan pilihan tetap seperti sebelumnya. Usulan yang sudah tercatat tidak berubah.",
    },
    {
      purpose: "companion_sharing",
      required: false,
      title: "Berbagi ringkasan mingguan dengan pendamping",
      description: "Orang yang kamu beri tautan pendamping (misalnya anggota keluarga) bisa melihat ringkasan mingguan: jumlah hari tercatat, menit aktivitas, jumlah konfirmasi obat, dan jam pengingat obat yang belum dikonfirmasi. Catatan mentah, nama makanan, nama obat, dan angka glukosa tidak ditampilkan.",
      dataCategories: ["Ringkasan mingguan yang dihitung dari catatanmu", "Jam pengingat obat yang belum dikonfirmasi"],
      withdrawalEffect: "Semua tautan pendamping berhenti berfungsi. Tautan bisa dibuat lagi bila kamu menyetujui kembali.",
    },
    {
      purpose: "device_data_coaching",
      required: false,
      title: "Memakai data perangkat untuk rencana kecil",
      description: "Memakai langkah, tidur, dan sesi latihan dari Health Connect (termasuk jam tangan yang tersambung) untuk menilai apakah rencana kecil terlaksana dan untuk memilih waktu saran. Data perangkat yang tidak lengkap atau ganda tidak pernah dianggap sebagai tidak aktif.",
      dataCategories: ["Langkah, tidur, dan sesi latihan dari perangkat"],
      withdrawalEffect: "Rencana dan saran hanya memakai catatan yang kamu masukkan sendiri. Data perangkat tetap tersimpan dan tampil di riwayatmu.",
    },
    {
      purpose: "social_outcomes_memory",
      required: false,
      title: "Memakai hasil tantangan untuk saran",
      description: "Memakai hasil tantangan dan misi tim yang kamu ikuti (hari aktif dan check-in, bukan nilai kesehatan) sebagai bahan refleksi mingguan dan ingatan asisten.",
      dataCategories: ["Hari aktif dan check-in tantangan"],
      withdrawalEffect: "Hasil tantangan tidak lagi dipakai untuk saran. Ingatan yang berasal darinya dijeda.",
    },
  ],
};

export const requiredPurposes: ConsentPurpose[] = currentPolicy.purposes.filter((p) => p.required).map((p) => p.purpose);
