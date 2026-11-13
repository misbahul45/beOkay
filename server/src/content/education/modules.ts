export type EducationContent = {
  key: string;
  version: number;
  title: string;
  summary: string;
  topics: string[];
  readMinutes: number;
  authoredOn: string;
  body: string;
};

const SOURCE_ADA = "American Diabetes Association. Standards of Care in Diabetes—2026.";
const SOURCE_ADA_PREVENTION = "American Diabetes Association. Standards of Care in Diabetes—2026, bagian Prevention or Delay of Diabetes.";
const SOURCE_WHO_ACTIVITY = "World Health Organization. WHO guidelines on physical activity and sedentary behaviour, 2020.";
const SOURCE_SLEEP = "Watson NF, dkk. Recommended Amount of Sleep for a Healthy Adult. Sleep 2015 (konsensus AASM dan SRS).";

export const EDUCATION_MODULES: EducationContent[] = [
  {
    key: "mengenal-dmt2",
    version: 1,
    title: "Mengenal diabetes tipe 2",
    summary: "Apa yang terjadi di tubuh, apa arti HbA1c, dan pemeriksaan rutin yang perlu dijadwalkan.",
    topics: ["dasar", "hba1c", "pemeriksaan"],
    readMinutes: 4,
    authoredOn: "2026-11-12",
    body: `## Apa yang terjadi
Pada diabetes tipe 2, tubuh tidak memakai insulin dengan baik dan lama-kelamaan produksinya bisa berkurang. Akibatnya gula tetap tinggi di dalam darah.

## Arti HbA1c
HbA1c menggambarkan rata-rata gula darah sekitar tiga bulan terakhir. Banyak orang dewasa diberi target sekitar di bawah 7%, tetapi targetmu ditentukan bersama dokter sesuai usia, kondisi, dan pengobatan.

## Pemeriksaan yang biasa dijadwalkan
- HbA1c: umumnya dua kali setahun bila stabil, lebih sering bila pengobatan berubah.
- Mata, ginjal (urin dan darah), kaki, tekanan darah, dan kolesterol: setidaknya setahun sekali, atau sesuai jadwal dari tenaga kesehatanmu.

## Yang bisa kamu lakukan
Mencatat makan, aktivitas, dan gula darah membantu kamu dan dokter melihat pola. Catatan bukan diagnosis; bawa ringkasannya saat kontrol.

## Sumber
${SOURCE_ADA}`,
  },
  {
    key: "karbohidrat-porsi",
    version: 1,
    title: "Karbohidrat dan porsi makan",
    summary: "Mengenali sumber karbohidrat dan cara sederhana menata piring.",
    topics: ["makan", "karbohidrat", "porsi"],
    readMinutes: 4,
    authoredOn: "2026-11-12",
    body: `## Mengapa karbohidrat
Karbohidrat paling banyak memengaruhi gula darah setelah makan. Sumbernya antara lain nasi, mi, roti, kentang, singkong, jagung, buah, dan minuman manis.

## Cara menata piring
Cara piring yang sering diajarkan: setengah piring sayur tanpa tepung, seperempat lauk berprotein (ikan, ayam, tempe, tahu, telur), dan seperempat makanan pokok. Cara ini bukan aturan mutlak; sesuaikan dengan saran ahli gizi atau doktermu.

## Kebiasaan yang membantu
- Porsi makanan pokok yang mirip dari hari ke hari memudahkan melihat pola gula darah.
- Pilih yang tinggi serat bila bisa, misalnya nasi merah atau sayur dan kacang-kacangan.
- Air putih lebih baik daripada minuman manis.

## Di beOkay
Nilai karbohidrat di beOkay berasal dari Tabel Komposisi Pangan Indonesia atau label kemasan. Angkanya perkiraan, bukan takaran pasti.

## Sumber
${SOURCE_ADA}`,
  },
  {
    key: "label-gizi",
    version: 1,
    title: "Membaca label gizi",
    summary: "Takaran saji, karbohidrat total, gula, serat, dan natrium pada Informasi Nilai Gizi.",
    topics: ["makan", "label"],
    readMinutes: 3,
    authoredOn: "2026-11-12",
    body: `## Mulai dari takaran saji
Semua angka di Informasi Nilai Gizi berlaku untuk satu takaran saji. Periksa berapa takaran saji dalam satu kemasan; bila kamu makan seluruh kemasan, kalikan angkanya.

## Angka yang paling berguna
- Karbohidrat total: termasuk gula dan pati.
- Gula: bagian dari karbohidrat total.
- Serat pangan: makin tinggi biasanya makin baik.
- Natrium: penting bila tekanan darahmu tinggi.

## Hati-hati dengan klaim
"Tanpa gula tambahan" tidak berarti tanpa karbohidrat. Lihat tetap angka karbohidrat total.

## Daftar bahan
Bahan ditulis dari yang paling banyak. Gula bisa muncul dengan nama lain seperti sirup glukosa, fruktosa, atau maltodekstrin.

## Sumber
${SOURCE_ADA}`,
  },
  {
    key: "hipoglikemia",
    version: 1,
    title: "Gula darah rendah (hipoglikemia)",
    summary: "Mengenali tanda gula darah rendah dan kapan harus segera mencari bantuan.",
    topics: ["glukosa", "darurat", "hipoglikemia"],
    readMinutes: 5,
    authoredOn: "2026-11-12",
    body: `## Apa itu
Gula darah di bawah 70 mg/dL (3,9 mmol/L) disebut rendah. Di bawah 54 mg/dL (3,0 mmol/L) tergolong berat. Risikonya lebih besar bila kamu memakai insulin atau obat jenis sulfonilurea.

## Tandanya
Gemetar, berkeringat, jantung berdebar, lapar mendadak, pusing, bingung, sulit bicara, atau mengantuk berat.

## Yang umum diajarkan
Banyak pedoman mengajarkan: makan atau minum sekitar 15 gram gula yang cepat diserap, periksa lagi setelah 15 menit, ulangi bila masih rendah. Pastikan cara ini sesuai rencana yang diberikan dokter atau tenaga kesehatanmu; tanyakan bila belum pernah dijelaskan.

## Segera cari bantuan bila
Pingsan, kejang, tidak bisa menelan, atau tidak membaik setelah penanganan: hubungi layanan gawat darurat. Ceritakan setiap kejadian gula rendah ke doktermu karena pengobatanmu mungkin perlu ditinjau.

## Sumber
${SOURCE_ADA}`,
  },
  {
    key: "perawatan-kaki",
    version: 1,
    title: "Merawat kaki",
    summary: "Pemeriksaan kaki harian dan tanda yang perlu segera diperiksakan.",
    topics: ["kaki", "komplikasi"],
    readMinutes: 4,
    authoredOn: "2026-11-12",
    body: `## Mengapa kaki
Diabetes dapat mengurangi rasa di kaki dan memperlambat penyembuhan luka. Luka kecil yang tidak terasa bisa menjadi serius.

## Kebiasaan harian
- Lihat telapak dan sela jari setiap hari; pakai cermin atau minta bantuan keluarga.
- Cuci dengan air hangat (bukan panas), keringkan sampai sela jari.
- Pakai alas kaki yang pas, juga di dalam rumah bila bisa.
- Potong kuku lurus; minta bantuan tenaga kesehatan bila kuku tebal atau sulit dipotong.

## Segera periksakan bila
Ada luka yang tidak membaik dalam beberapa hari, bernanah, kulit menghitam atau membiru, bengkak, atau terasa panas.

## Pemeriksaan rutin
Mintalah pemeriksaan kaki lengkap oleh tenaga kesehatan setidaknya setahun sekali.

## Sumber
${SOURCE_ADA}`,
  },
  {
    key: "saat-sakit",
    version: 1,
    title: "Saat sedang sakit",
    summary: "Demam, flu, atau diare bisa membuat gula darah naik turun. Siapkan rencana hari sakit.",
    topics: ["sakit", "glukosa"],
    readMinutes: 4,
    authoredOn: "2026-11-12",
    body: `## Mengapa perlu rencana
Saat sakit, tubuh melepaskan hormon stres yang dapat menaikkan gula darah. Muntah atau diare juga membuat tubuh kekurangan cairan.

## Yang umum dianjurkan
- Tetap minum cukup cairan sedikit-sedikit tapi sering.
- Bila nafsu makan turun, makan porsi kecil yang mudah dicerna.
- Periksa gula darah lebih sering bila kamu punya alat.
- Jangan menghentikan atau mengubah obat sendiri. Beberapa obat memang perlu disesuaikan saat sakit berat, tetapi itu keputusan doktermu.

## Tanyakan sebelum sakit
Mintalah "rencana hari sakit" ke doktermu saat kontrol berikutnya, termasuk obat mana yang perlu diperhatikan.

## Segera cari bantuan bila
Muntah berulang, tidak bisa minum, sangat lemas atau mengantuk, napas cepat, atau gula darah terus sangat tinggi.

## Sumber
${SOURCE_ADA}`,
  },
  {
    key: "puasa-ramadan",
    version: 1,
    title: "Puasa Ramadan dengan diabetes",
    summary: "Persiapan bersama dokter, pemeriksaan selama puasa, dan kapan membatalkan puasa.",
    topics: ["puasa", "makan", "glukosa"],
    readMinutes: 5,
    authoredOn: "2026-11-12",
    body: `## Bicarakan lebih dulu
Temui dokter beberapa minggu sebelum Ramadan. Dokter menilai apakah puasa aman untukmu dan apakah jadwal obat perlu diatur ulang.

## Selama puasa
- Memeriksa gula darah dengan tusuk jari tidak membatalkan puasa menurut pedoman yang disusun bersama ulama.
- Sahur sedekat mungkin dengan imsak; pilih makanan tinggi serat dan protein.
- Saat berbuka, hindari makan berlebihan dan minuman sangat manis; cukupkan minum air sampai sahur.

## Kapan membatalkan puasa
Pedoman internasional menganjurkan membatalkan puasa bila gula darah di bawah 70 mg/dL atau di atas 300 mg/dL, atau bila muncul tanda gula rendah, bingung, pingsan, atau sakit.

## Di beOkay
Kamu bisa menyimpan "sedang berpuasa" sebagai kondisi sementara di Memori agar saran menyesuaikan.

## Sumber
International Diabetes Federation & DAR International Alliance. Diabetes and Ramadan: Practical Guidelines 2021.`,
  },
  {
    key: "obat-bertanya-dokter",
    version: 1,
    title: "Obat: kapan bertanya ke dokter",
    summary: "beOkay tidak memberi saran obat. Ini daftar situasi yang perlu kamu tanyakan.",
    topics: ["obat"],
    readMinutes: 3,
    authoredOn: "2026-11-12",
    body: `## Tanyakan ke dokter atau apoteker bila
- Ingin menghentikan, mengganti, atau mengubah takaran obat.
- Sering lupa minum obat atau ragu apa yang harus dilakukan setelah lupa.
- Muncul efek samping, misalnya mual terus, diare, atau gula darah sering rendah.
- Mulai memakai obat lain, jamu, atau suplemen.
- Akan berpuasa, bepergian jauh, atau sedang sakit.

## Siapkan sebelum kontrol
Bawa daftar semua obat dan suplemen, jam minumnya, dan ringkasan catatan dari beOkay. Tulis pertanyaanmu lebih dulu agar tidak terlupa.

## Mengapa beOkay tidak menjawab soal obat
Keputusan obat membutuhkan pemeriksaan dan riwayat lengkap. beOkay membantu mencatat dan mengingatkan; keputusan tetap di tangan tenaga kesehatanmu.

## Sumber
${SOURCE_ADA}`,
  },
  {
    key: "aktivitas-aman",
    version: 1,
    title: "Bergerak dengan aman",
    summary: "Target aktivitas yang umum, cara memulai pelan, dan tanda untuk berhenti.",
    topics: ["aktivitas"],
    readMinutes: 4,
    authoredOn: "2026-11-12",
    body: `## Target yang umum
Banyak pedoman menyarankan sekitar 150 menit aktivitas sedang per minggu, dibagi ke beberapa hari, ditambah latihan otot dua sampai tiga kali seminggu. Kalau belum terbiasa, mulai dari 5–10 menit sudah berarti.

## Kebiasaan yang membantu
- Selingi duduk lama dengan berdiri atau berjalan sebentar setiap setengah jam.
- Pakai alas kaki yang nyaman dan periksa kaki setelah beraktivitas.
- Minum air yang cukup.

## Hati-hati bila
Kamu memakai insulin atau obat yang dapat menurunkan gula darah: tanyakan ke dokter cara mencegah gula rendah saat beraktivitas.

## Berhenti dan cari bantuan bila
Nyeri dada, sesak napas berat, pusing hebat, atau jantung berdebar tidak biasa.

## Sumber
${SOURCE_ADA}`,
  },
  {
    key: "cek-gula-mandiri",
    version: 1,
    title: "Memeriksa gula darah sendiri",
    summary: "Cara periksa dengan glukometer, mencatat konteksnya, dan memahami sensor (CGM).",
    topics: ["glukosa", "cgm", "pemantauan"],
    readMinutes: 4,
    authoredOn: "2026-11-12",
    body: `## Dengan glukometer
- Cuci dan keringkan tangan sebelum menusuk jari.
- Catat waktunya dan keadaannya: puasa, sebelum makan, setelah makan, atau sebelum tidur.
- Seberapa sering perlu memeriksa tergantung pengobatanmu; tanyakan ke dokter.

## Dengan sensor (CGM)
Sensor mengukur cairan di bawah kulit, sehingga angkanya sedikit tertinggal beberapa menit dibanding darah jari. Ringkasan yang sering dipakai adalah waktu dalam rentang 70–180 mg/dL. Untuk banyak orang dewasa, konsensus internasional menyarankan lebih dari 70% waktu berada di rentang itu dan kurang dari 4% di bawah 70 mg/dL; targetmu tetap ditentukan bersama dokter.

## Di beOkay
Ringkasan sensor di beOkay bersifat deskriptif. beOkay tidak memberi saran dosis berdasarkan angka sensor.

## Sumber
${SOURCE_ADA} Battelino T, dkk. International Consensus on Time in Range. Diabetes Care 2019.`,
  },
  {
    key: "cegah-diabetes",
    version: 1,
    title: "Mencegah atau menunda diabetes tipe 2",
    summary: "Bila tenaga kesehatan menyebut kamu prediabetes atau berisiko: apa artinya dan kebiasaan yang biasa dianjurkan.",
    topics: ["pencegahan", "prediabetes", "kebiasaan"],
    readMinutes: 4,
    authoredOn: "2026-11-13",
    body: `## Apa artinya berisiko
Prediabetes berarti kadar gula darah lebih tinggi dari biasa, tetapi belum masuk kriteria diabetes. Hanya tenaga kesehatan yang dapat menetapkannya dari hasil pemeriksaan. beOkay tidak menilai risikomu dari catatan.

## Kebiasaan yang biasa dianjurkan
- Bergerak lebih sering. Langkah kecil yang rutin lebih mudah dipertahankan daripada target besar.
- Mengatur porsi dan memilih makanan berserat lebih sering.
- Tidur yang cukup dan teratur.
- Bila tenaga kesehatanmu menyarankan menurunkan berat badan, target dan caranya ditentukan bersama mereka.

## Yang tidak dilakukan beOkay
beOkay tidak mendiagnosis, tidak memberi target berat badan, dan tidak menggantikan pemeriksaan rutin.

## Sumber
${SOURCE_ADA_PREVENTION}`,
  },
  {
    key: "pemeriksaan-rutin",
    version: 1,
    title: "Pemeriksaan rutin",
    summary: "Mengapa pemeriksaan berkala penting dan siapa yang menentukan jadwalnya.",
    topics: ["pemeriksaan", "pencegahan"],
    readMinutes: 3,
    authoredOn: "2026-11-13",
    body: `## Mengapa penting
Banyak perubahan gula darah tidak terasa. Pemeriksaan berkala membantu tenaga kesehatan melihatnya lebih awal.

## Siapa yang menentukan jadwal
Seberapa sering kamu perlu diperiksa ditentukan tenaga kesehatanmu sesuai usia, riwayat keluarga, dan hasil sebelumnya. beOkay hanya dapat mengingatkan jadwal yang kamu masukkan sendiri.

## Bila ada keluhan
Bila kamu sering haus, sering buang air kecil, mudah lelah, atau luka sulit sembuh, periksakan diri ke fasilitas kesehatan.

## Sumber
${SOURCE_ADA_PREVENTION}`,
  },
  {
    key: "tidur-dan-pulih",
    version: 1,
    title: "Tidur dan pemulihan",
    summary: "Kebiasaan tidur yang mendukung energi harian, dan cara membaca data tidur dari perangkat.",
    topics: ["tidur", "pemulihan", "perangkat"],
    readMinutes: 3,
    authoredOn: "2026-11-13",
    body: `## Tidur yang cukup
Konsensus untuk orang dewasa menyebut tidur 7 jam atau lebih per malam secara teratur. Kebutuhan tiap orang berbeda.

## Kebiasaan yang membantu
- Jam tidur dan bangun yang mirip setiap hari.
- Mengurangi layar dan kafein menjelang tidur.
- Bergerak di siang hari.

## Data tidur dari perangkat
Jam tangan dan ponsel memperkirakan tidur dari gerakan dan detak jantung. Angkanya perkiraan, bisa terlewat bila perangkat tidak dipakai, dan tidak dipakai beOkay untuk menilai kesehatanmu.

## Bila tidur terus terganggu
Mendengkur keras, terbangun sesak, atau kantuk berat di siang hari perlu dibicarakan dengan tenaga kesehatan.

## Sumber
${SOURCE_SLEEP} ${SOURCE_WHO_ACTIVITY}`,
  },
];

export const MODULE_JOURNEYS: Record<string, readonly ("PREVENTION" | "T2DM_SUPPORT" | "WELLNESS" | "UNDETERMINED")[]> = {
  "mengenal-dmt2": ["T2DM_SUPPORT", "UNDETERMINED"],
  "karbohidrat-porsi": ["PREVENTION", "T2DM_SUPPORT", "WELLNESS", "UNDETERMINED"],
  "label-gizi": ["PREVENTION", "T2DM_SUPPORT", "WELLNESS", "UNDETERMINED"],
  hipoglikemia: ["T2DM_SUPPORT", "UNDETERMINED"],
  "perawatan-kaki": ["T2DM_SUPPORT", "UNDETERMINED"],
  "saat-sakit": ["T2DM_SUPPORT", "UNDETERMINED"],
  "puasa-ramadan": ["T2DM_SUPPORT", "UNDETERMINED"],
  "obat-bertanya-dokter": ["T2DM_SUPPORT", "UNDETERMINED"],
  "aktivitas-aman": ["PREVENTION", "T2DM_SUPPORT", "WELLNESS", "UNDETERMINED"],
  "cek-gula-mandiri": ["T2DM_SUPPORT", "UNDETERMINED"],
  "cegah-diabetes": ["PREVENTION"],
  "pemeriksaan-rutin": ["PREVENTION", "WELLNESS"],
  "tidur-dan-pulih": ["PREVENTION", "T2DM_SUPPORT", "WELLNESS", "UNDETERMINED"],
};
