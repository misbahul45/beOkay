# beOkay 3.0 — Master Product & Engineering Blueprint

Product Vision · System Architecture · Hybrid Agentic AI · Modal ML · Nutrition Intelligence · Wearable Monitoring · Community Gamification

Status dokumen: Target architecture & development specification — 8 November 2026

beOkay akan dikembangkan menjadi Preventive Metabolic Intelligence & Community Ecosystem, yaitu platform mobile yang membantu individu dengan prediabetes atau diabetes tipe 2 tahap pengelolaan dini membangun kebiasaan hidup lebih sehat melalui personalisasi nutrisi, aktivitas fisik, pemantauan kesehatan, Hybrid Agentic AI, dan dukungan komunitas.

Platform ini bukan sekadar aplikasi pencatatan glukosa atau kalori. beOkay dirancang sebagai sistem yang menghubungkan data → pemahaman → pilihan tindakan → pelaksanaan → evaluasi → penyesuaian personal.

CORE PRODUCT VALUE

## Know your habits. Understand your patterns. Improve together.

Preventive Care

Personal AI

Community

## 1. Product direction: masalah sebenarnya yang diselesaikan

Banyak aplikasi kesehatan mampu mencatat makanan, glukosa, dan aktivitas. Tetapi pencatatan tidak otomatis membuat seseorang memahami kebiasaannya atau mengubah perilakunya.

beOkay perlu berfokus pada enam masalah berikut.

| Masalah                                                     | Kebutuhan pengguna                          | Respons sistem                       |
| ----------------------------------------------------------- | ------------------------------------------- | ------------------------------------ |
| Tidak memahami kaitan kebiasaan dan data kesehatan          | Penjelasan personal yang dapat dipercaya    | Evidence-grounded insights           |
| Sulit menentukan pilihan makanan                            | Alternatif makanan realistis dan terjangkau | Nutrition Search & Personalization   |
| Tidak konsisten beraktivitas fisik                          | Rencana sesuai kemampuan dan waktu          | Adaptive Activity Planning           |
| Pencatatan manual melelahkan                                | Pencatatan cepat dan sinkronisasi otomatis  | Wearable & Smart Logging             |
| Motivasi perubahan perilaku cepat menurun                   | Tujuan kecil, feedback, dukungan sosial     | Habit Coaching & Challenges          |
| Sulit menemukan dukungan dari orang dengan kebutuhan serupa | Komunitas yang aman dan sukarela            | Privacy-Preserving Local Communities |

### 1.1 Fokus pencegahan harus tepat

Istilah "diabetes yang belum parah" perlu diterjemahkan ke segmentasi yang benar.

Segmen A — Prediabetes

Individu yang memiliki status prediabetes berdasarkan hasil pemeriksaan/penilaian klinis. Fokusnya mendukung kebiasaan yang dapat membantu mengurangi risiko progresi menjadi diabetes tipe 2.

Segmen B — Diabetes Tipe 2 Terdiagnosis

Individu yang sesuai untuk program pendampingan kebiasaan. Fokusnya mendukung self-management, konsistensi aktivitas, pemahaman pola, dan pencegahan komplikasi sebagai pelengkap perawatan.

Segmen C — Individu dengan Faktor Risiko

Dapat menggunakan edukasi dan pencatatan gaya hidup umum, tetapi tidak memperoleh diagnosis atau klasifikasi klinis otomatis dari AI.

Untuk MVP, aku menyarankan orang dewasa dengan prediabetes atau T2DM terdiagnosis, dengan eligibility yang jelas sebelum fitur aktivitas dan nutrisi personal diaktifkan.

ADA Standards of Care 2026 mendukung intervensi gaya hidup terstruktur dan program pencegahan berbantuan teknologi untuk populasi yang sesuai. Ini menjadi landasan domain masalah, bukan bukti bahwa beOkay sudah memberikan manfaat klinis.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://doi.org\&sz=32)

DOI+1



### 1.2 Batasan produk

beOkay dirancang sebagai behavioral support and health self-management platform, bukan perangkat diagnosis, pengganti dokter, atau pemberi resep otomatis.

AI tidak boleh menentukan seseorang mengidap diabetes, mengubah dosis obat, menyatakan kadar glukosa aman berdasarkan smartwatch, atau mengklaim bahwa satu jenis makanan/olahraga menyebabkan perbaikan klinis berdasarkan observasi terbatas.

Fitur yang berpotensi menjadi clinical decision support harus melalui penilaian keselamatan, validasi, dan tinjauan regulasi sebelum diaktifkan.

## 2. Kondisi proyek sebelumnya: apa yang dipertahankan?

Bagian ini penting karena beOkay sudah memiliki fondasi yang tidak perlu dibuat ulang.

Berdasarkan laporan repository yang kamu lampirkan, fondasi proyek menggunakan:

| Layer                    | Existing technology                              | Keputusan       |
| ------------------------ | ------------------------------------------------ | --------------- |
| Mobile                   | Flutter, Dart, Riverpod, go_router               | Pertahankan     |
| Backend                  | Bun dengan `Bun.serve` dan feature-based modules | Pertahankan     |
| Database                 | PostgreSQL + Prisma 7                            | Pertahankan     |
| Authentication           | Better Auth                                      | Pertahankan     |
| Validation               | Zod                                              | Pertahankan     |
| API testing              | Bruno                                            | Pertahankan     |
| Backend testing          | `bun:test`                                       | Pertahankan     |
| Mobile testing           | Flutter tests + Appium                           | Pertahankan     |
| Design                   | Existing FigCraft project dan design tokens      | Kembangkan      |
| Agentic AI               | Belum ada dalam implementasi yang ditunjukkan    | Layanan baru    |
| ML Inference             | Belum ada                                        | Deploy di Modal |
| Community & Gamification | Belum ada                                        | Domain baru     |

Keputusan penting: jangan mengganti `Bun.serve` menjadi NestJS, mengganti Prisma menjadi Drizzle, atau menulis ulang Better Auth hanya karena menambahkan kemampuan AI. Audit repository secara eksplisit mencatat stack aktual tersebut.&#x20;

Pasted text(20261108-155419).txt



### 2.1 Existing feature audit

| Auth, consent, onboarding, profile             | Fondasi tersedia; perlu pemeriksaan keselamatan dan regresi      |
| ---------------------------------------------- | ---------------------------------------------------------------- |
| Nutrition                                      | Online logging, food catalog, history, corrections, revisions    |
| Glucose                                        | Manual observations, unit conversion, source, history, revisions |
| Activity                                       | Manual sessions, daily/weekly summaries, corrections             |
| Today & Timeline                               | Integrasi tiga domain kesehatan sudah dilaporkan                 |
| Medication, Goals, Offline, Full Insights      | Masih dalam rencana penyelesaian P0 pada snapshot                |
| Food Search Agent, Modal, Wearables, Community | Belum ada bukti implementasi dalam snapshot                      |

Status berdasarkan dokumentasi dan laporan yang disertakan dalam Repomix, bukan audit ulang terhadap working tree terbaru atau deployment produksi.&#x20;

Pasted text(20261108-155419).txt

Pasted text(20261108-155419).txt

Dalam laporan Activity terakhir, sudah tercatat 15 pengujian backend lulus, 52 tes Flutter lulus, 57/57 request/test Bruno lulus, dan 10 pemeriksaan alur Appium. Cakupannya masih terbatas pada fitur yang telah dikerjakan.&#x20;

Pasted text(20261108-155419).txt



### 2.2 Prinsip pengembangan dari versi sebelumnya

Kita akan melakukan incremental architecture evolution.

\#chatgpt-mermaid-\_r_vn\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_vn\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_vn\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_vn\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_vn\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_vn\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_vn\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_vn\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_vn\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_vn\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_vn\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_vn\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_vn\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_vn\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_vn\_ p{margin:0;}#chatgpt-mermaid-\_r_vn\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_vn\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_vn\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_vn\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_vn\_ .label text,#chatgpt-mermaid-\_r_vn\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_vn\_ .node rect,#chatgpt-mermaid-\_r_vn\_ .node circle,#chatgpt-mermaid-\_r_vn\_ .node ellipse,#chatgpt-mermaid-\_r_vn\_ .node polygon,#chatgpt-mermaid-\_r_vn\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_vn\_ .rough-node .label text,#chatgpt-mermaid-\_r_vn\_ .node .label text,#chatgpt-mermaid-\_r_vn\_ .image-shape .label,#chatgpt-mermaid-\_r_vn\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_vn\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_vn\_ .rough-node .label,#chatgpt-mermaid-\_r_vn\_ .node .label,#chatgpt-mermaid-\_r_vn\_ .image-shape .label,#chatgpt-mermaid-\_r_vn\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_vn\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_vn\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_vn\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_vn\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_vn\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_vn\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_vn\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_vn\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_vn\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_vn\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_vn\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_vn\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_vn\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_vn\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_vn\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_vn\_ .icon-shape,#chatgpt-mermaid-\_r_vn\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_vn\_ .icon-shape p,#chatgpt-mermaid-\_r_vn\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_vn\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_vn\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_vn\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_vn\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_vn\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_vn\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_vn\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_vn\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_vn\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_vn\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_vn\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_vn\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_vn\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_vn\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_vn\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_vn\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_vn\_ .node rect,#chatgpt-mermaid-\_r_vn\_ .node circle,#chatgpt-mermaid-\_r_vn\_ .node ellipse,#chatgpt-mermaid-\_r_vn\_ .node polygon,#chatgpt-mermaid-\_r_vn\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_vn\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_vn\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_vn\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_vn\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_vn\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}beOkay Existing CoreComplete P0Nutrition IntelligenceWearable DataHybrid Agentic + Modal MLCommunity & GamificationValidated PreventiveEcosystem

Satu hal yang harus dipertahankan adalah data integrity. Sistem sebelumnya sudah membedakan missing values dari nol, menyimpan nutrition snapshots, serta menggunakan optimistic concurrency dan revision history. Perluasan AI tidak boleh menghilangkan sifat-sifat tersebut.

## 3. Enam pilar produk akhir

1\. Personal Health Tracking

Makanan, glukosa, aktivitas, obat, goals, timeline, dan insight deskriptif.

2\. Nutrition Intelligence

Pencarian makanan, verifikasi kalori, personalisasi menu, dan food recognition opsional.

3\. Adaptive Activity

Rencana aktivitas dan pelacakan melalui smartwatch yang kompatibel.

4\. Hybrid AI Intelligence

LLM agents, deterministic rules, ML inference di Modal, dan evidence validation.

5\. Behavioral Coaching

Micro-goals, reminders yang relevan, feedback, dan personal action planning.

6\. Community Motivation

Komunitas berbasis wilayah pilihan, challenges, achievements, dan leaderboard yang aman.

Keenam pilar tersebut harus terhubung melalui satu model data dan satu alur pengalaman pengguna. Namun, setiap pilar tetap mempunyai batas kepemilikan data dan tanggung jawab yang jelas.

## 4. Target system architecture — end-to-end

Arsitektur final sebaiknya memakai pendekatan Modular Core + Specialized Intelligence Services.

Artinya, tidak semua domain perlu menjadi microservice. Domain transaksi pengguna tetap berada dalam satu backend modular, sedangkan AI orchestration dan ML inference dipisahkan karena memiliki runtime, dependensi, dan pola scaling yang berbeda.

\#chatgpt-mermaid-\_r_10j\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_10j\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_10j\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_10j\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_10j\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_10j\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_10j\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_10j\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_10j\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_10j\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_10j\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_10j\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_10j\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_10j\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_10j\_ p{margin:0;}#chatgpt-mermaid-\_r_10j\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_10j\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_10j\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_10j\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_10j\_ .label text,#chatgpt-mermaid-\_r_10j\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_10j\_ .node rect,#chatgpt-mermaid-\_r_10j\_ .node circle,#chatgpt-mermaid-\_r_10j\_ .node ellipse,#chatgpt-mermaid-\_r_10j\_ .node polygon,#chatgpt-mermaid-\_r_10j\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_10j\_ .rough-node .label text,#chatgpt-mermaid-\_r_10j\_ .node .label text,#chatgpt-mermaid-\_r_10j\_ .image-shape .label,#chatgpt-mermaid-\_r_10j\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_10j\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_10j\_ .rough-node .label,#chatgpt-mermaid-\_r_10j\_ .node .label,#chatgpt-mermaid-\_r_10j\_ .image-shape .label,#chatgpt-mermaid-\_r_10j\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_10j\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_10j\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_10j\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_10j\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_10j\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_10j\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_10j\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_10j\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_10j\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_10j\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_10j\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_10j\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_10j\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_10j\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_10j\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_10j\_ .icon-shape,#chatgpt-mermaid-\_r_10j\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_10j\_ .icon-shape p,#chatgpt-mermaid-\_r_10j\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_10j\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_10j\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_10j\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_10j\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_10j\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_10j\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_10j\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_10j\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_10j\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_10j\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_10j\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_10j\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_10j\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_10j\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_10j\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_10j\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_10j\_ .node rect,#chatgpt-mermaid-\_r_10j\_ .node circle,#chatgpt-mermaid-\_r_10j\_ .node ellipse,#chatgpt-mermaid-\_r_10j\_ .node polygon,#chatgpt-mermaid-\_r_10j\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_10j\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_10j\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_10j\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_10j\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_10j\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}05 — External Services04 — Hybrid Intelligence · Python03 — Data & Events02 — Core Platform · Bun API01 — Client LayerNutrition Database APIsSearch Engine APIModal ML InferencePersonal Context BuilderLangGraph OrchestratorConstrained Agent ToolsRules & Safety EngineCurated Knowledge RetrievalPostgreSQL + PrismaOutbox + Worker QueueRedis CacheObject StorageBetter Auth + ConsentHealth TrackingNutrition DomainActivity & GoalsSummaries & InsightsCommunity & ChallengesAI GatewayFlutter Mobile AppSmartwatch / WearableHealth Connect / HealthKit

### 4.1 Tanggung jawab setiap layer

| Layer            | Responsibility                                                       | Tidak boleh dilakukan                                   |
| ---------------- | -------------------------------------------------------------------- | ------------------------------------------------------- |
| Flutter          | Input, visualisasi, konfirmasi, local cache, wearable permissions    | Mengakses Modal langsung dengan secret                  |
| Bun Core API     | Auth, consent, business rules, persistence, ownership, API contracts | Menjalankan LLM inference secara langsung               |
| PostgreSQL       | Source of truth dan transaction integrity                            | Menjadikan hasil prediksi sebagai data pengukuran       |
| Agent Service    | Intent understanding, orchestration, tool execution, explanation     | Mengubah data medis atau terapi tanpa izin              |
| Modal            | Inference untuk model yang sudah dideploy                            | Mengelola identitas dan seluruh health records          |
| Search Engine    | Menemukan kandidat sumber informasi nutrisi                          | Menentukan otomatis bahwa angka web akurat              |
| Community Engine | Challenges, points, rankings, moderation                             | Mengakses atau mempublikasikan catatan kesehatan privat |

### 4.2 Communication pattern

Aku menyarankan tiga pola komunikasi.

Synchronous REST untuk login, pencatatan, membaca timeline, mengambil daftar challenge, dan meminta hasil yang relatif cepat.

Asynchronous event processing untuk sinkronisasi wearable, perhitungan ulang summary, pemrosesan foto makanan, background analysis, serta pemutakhiran leaderboard.

Streaming SSE khusus untuk respons AI yang membutuhkan waktu lebih panjang. Streaming hanya menyampaikan status dan output yang telah diperiksa sesuai tahapannya. Tidak semua intermediate reasoning agent perlu diekspos kepada pengguna.

Contoh event internal:

```
{
  "event_id": "evt_001",
  "type": "health.meal.recorded.v1",
  "aggregate_id": "meal_001",
  "aggregate_version": 1,
  "occurred_at": "2026-11-08T05:15:00Z",
  "payload": {
    "record_id": "meal_001"
  }
}
```

Event ini tidak perlu membawa nama pengguna, nilai glukosa, atau data kesehatan lengkap. Worker dapat mengambil data yang benar-benar dibutuhkan melalui layanan berizin.

Untuk reliability, gunakan transactional outbox agar perubahan database dan pencatatan event tidak mudah terpisah saat terjadi crash. Consumer bersifat idempoten dan memproses ulang event secara aman.

# PART A — HYBRID AGENTIC AI SYSTEM

## 5. Apa arti Hybrid Agentic pada beOkay?

Kita tidak membangun chatbot dengan banyak nama agent. Kita membangun sistem keputusan terstruktur yang menggunakan AI hanya ketika AI memberikan manfaat nyata.

Ada empat jenis komputasi.

Deterministic Engine

Validasi data, kalkulasi nutrisi, eligibility, pemeriksaan keselamatan, pengolahan poin, permission, dan aturan yang harus menghasilkan keluaran konsisten.

Statistical & ML Engine

Personal baseline, trend analysis, candidate ranking, adherence modeling, dan klasifikasi makanan. Model ML khusus dijalankan melalui Modal.

LLM Agentic Reasoning

Memahami kebutuhan bahasa alami, mengatur pemanggilan tools, menafsirkan hasil yang telah diverifikasi, dan menghasilkan penjelasan yang mudah dipahami.

Evidence Retrieval

Referensi nutrisi, panduan gaya hidup, dan knowledge base yang memiliki sumber, versi, cakupan, dan tanggal peninjauan.

Pembagian ini penting karena misalnya menghitung 150 gram nasi dari nilai nutrisi per 100 gram tidak memerlukan LLM. Begitu pula memberi 80 poin untuk penyelesaian goal tidak memerlukan model Machine Learning.

## 6. Agent architecture dan tanggung jawab

| Orchestrator                | Menentukan intent, alur, tool yang diperbolehkan, dependency, dan output contract.                                   |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Food Search Agent           | Mencari kandidat makanan, referensi nutrisi, dan informasi porsi; menyerahkan perhitungan ke nutrition calculator.   |
| Nutrition Planning Agent    | Menyusun dan menjelaskan opsi makanan sesuai preferensi dan constraint yang divalidasi.                              |
| Activity Planning Agent     | Mengurutkan opsi aktivitas yang layak dan mendukung perencanaan jadwal.                                              |
| Metabolic Insight Agent     | Menginterpretasi hasil statistik, data coverage, dan pola temporal tanpa membuat klaim kausal.                       |
| Behavior Coach Agent        | Membantu refleksi, hambatan kebiasaan, motivasi, dan micro-goal yang dipilih pengguna.                               |
| Community Assistant         | Membantu menemukan challenge serta komunitas yang diikuti secara sukarela, tanpa mengungkap data anggota.            |
| Evidence & Safety Validator | Policy engine deterministik yang menentukan apakah suatu rekomendasi dapat ditampilkan, perlu review, atau diblokir. |

Semua komponen tersebut tidak harus berupa LLM independen. Aku memilih satu orchestrator, beberapa task-specific workflows, dan satu set tool terstruktur. Ini lebih mudah dipelihara daripada tujuh agent yang berdiskusi tanpa kontrol.

## 7. LangGraph state machine

Inilah workflow utama untuk setiap permintaan yang membutuhkan personalisasi.

\#chatgpt-mermaid-\_r_11d\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_11d\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_11d\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_11d\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_11d\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11d\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_11d\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_11d\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_11d\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_11d\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_11d\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_11d\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11d\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11d\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_11d\_ p{margin:0;}#chatgpt-mermaid-\_r_11d\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11d\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11d\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11d\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_11d\_ .label text,#chatgpt-mermaid-\_r_11d\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11d\_ .node rect,#chatgpt-mermaid-\_r_11d\_ .node circle,#chatgpt-mermaid-\_r_11d\_ .node ellipse,#chatgpt-mermaid-\_r_11d\_ .node polygon,#chatgpt-mermaid-\_r_11d\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_11d\_ .rough-node .label text,#chatgpt-mermaid-\_r_11d\_ .node .label text,#chatgpt-mermaid-\_r_11d\_ .image-shape .label,#chatgpt-mermaid-\_r_11d\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_11d\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_11d\_ .rough-node .label,#chatgpt-mermaid-\_r_11d\_ .node .label,#chatgpt-mermaid-\_r_11d\_ .image-shape .label,#chatgpt-mermaid-\_r_11d\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_11d\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_11d\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11d\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11d\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_11d\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_11d\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_11d\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_11d\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_11d\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_11d\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_11d\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11d\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11d\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_11d\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11d\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_11d\_ .icon-shape,#chatgpt-mermaid-\_r_11d\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_11d\_ .icon-shape p,#chatgpt-mermaid-\_r_11d\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_11d\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_11d\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_11d\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_11d\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_11d\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_11d\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_11d\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_11d\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_11d\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11d\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_11d\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11d\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_11d\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_11d\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_11d\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_11d\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_11d\_ .node rect,#chatgpt-mermaid-\_r_11d\_ .node circle,#chatgpt-mermaid-\_r_11d\_ .node ellipse,#chatgpt-mermaid-\_r_11d\_ .node polygon,#chatgpt-mermaid-\_r_11d\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_11d\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_11d\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_11d\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_11d\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11d\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}User Intent / TriggerIntent ClassificationConsent & Eligibility?Build Minimum PersonalContextData Sufficient?Ask User / Offer Basic ModePlan Tool ExecutionSearch / Analytics / Modal /RAGValidate Tool OutputsGenerate Candidate ActionsSafety PolicyRequires Confirmation?User Reviews & ConfirmsExplainable ResponseSave Decision MetadataRestricted Response / ReferralNoYesNoYesBlockedAllowedYesNo

### 7.1 LangGraph State Contract

Setiap invocation memiliki state terstruktur seperti berikut:

```

type AgentState = {
  runId: string;
  intent: AgentIntent;
  userQuery: string;

  consentScopes: string[];
  contextVersion: string;

  // References, not unrestricted personal records
  contextRefs: string[];
  dataCoverage: "SUFFICIENT" | "PARTIAL" | "INSUFFICIENT";

  toolResults: ToolResult[];
  evidenceRefs: EvidenceRef[];

  candidates: CandidateAction[];
  safetyStatus:
    | "APPROVED"
    | "NEEDS_CONFIRMATION"
    | "NEEDS_CLINICAL_REVIEW"
    | "BLOCKED";

  finalResponse?: AgentResponse;
};

```

Ini merupakan kontrak usulan, bukan tipe yang telah ada dalam kode saat ini.

### 7.2 Tool registry

Agent hanya memiliki akses ke tools yang sudah ditentukan secara eksplisit.

| Tool                           | Input                                   | Output                          |
| ------------------------------ | --------------------------------------- | ------------------------------- |
| `get_personal_context`         | Authenticated subject, requested scopes | Data minimal yang diizinkan     |
| `search_food_catalog`          | Food query                              | Kandidat makanan                |
| `search_external_food_sources` | Sanitized query                         | Kandidat sumber + metadata      |
| `calculate_nutrition`          | Verified nutrients, grams               | Nilai nutrisi + coverage        |
| `get_activity_summary`         | Date range                              | Aktivitas dan data quality      |
| `get_glucose_summary`          | Date range                              | Statistik pengukuran yang layak |
| `rank_meal_candidates`         | Eligible candidates                     | Ranking dan alasan              |
| `rank_activity_candidates`     | Eligible activities                     | Ranking dan alasan              |
| `request_modal_inference`      | Model ID + validated feature vector     | Prediksi dan model version      |
| `retrieve_health_evidence`     | Bounded topic                           | Referensi yang dikurasi         |
| `get_eligible_challenges`      | User-safe eligibility + selected region | Tantangan yang boleh diikuti    |

Tool tidak menerima `user_id` dari teks pesan sebagai otorisasi. Identitas diambil dari authenticated backend context.

Agent tidak diberi akses untuk menjalankan SQL arbitrer, mengubah obat, memodifikasi nilai glukosa, atau mempublikasikan data komunitas tanpa proses API yang benar.

### 7.3 Dua workflow intelligence

Fast Loop — Event-driven

Untuk meal recorded, activity synced, goal checked in, atau data correction. Server memperbarui read model, menjalankan kalkulasi deterministik, dan menjadwalkan analisis yang relevan.

Slow Loop — Daily/Weekly Review

Untuk analisis pola longitudinal, evaluasi ketercapaian goals, rekomendasi rencana berikutnya, dan penyesuaian coaching.

Fast loop tidak perlu melakukan inference berat setiap kali satu data masuk. Slow loop tidak perlu menyisir seluruh history setiap kali pengguna membuka layar.

### 7.4 Human-in-the-loop

Pengguna harus memiliki kontrol atas tindakan yang memengaruhi jadwal, goals, makanan, dan interaksi komunitas.

| Keputusan                               | Boleh otomatis?     |
| --------------------------------------- | ------------------- |
| Menghitung total nutrisi yang valid     | Ya                  |
| Memperbarui ringkasan aktivitas         | Ya                  |
| Menganalisis konsistensi kebiasaan      | Ya, dengan izin     |
| Membuat kandidat meal plan              | Ya                  |
| Mengaktifkan meal plan sebagai goal     | Konfirmasi pengguna |
| Menjadwalkan reminder baru              | Konfirmasi pengguna |
| Bergabung dengan challenge              | Konfirmasi pengguna |
| Mengubah regimen atau dosis obat        | Tidak               |
| Mengirim data kesehatan ke peserta lain | Tidak               |

## 8. Cara kerja agent pada percakapan nyata

Contoh pengguna bertanya:

> "Aku mau makan siang yang tidak terlalu mahal, tapi aku juga ingin tetap menjalankan kebiasaan makan lebih baik. Setelah itu aku ada waktu 20 menit buat jalan."

Sistem tidak cukup menjawab dengan daftar makanan dan olahraga generik.

Safety PolicyModalFood SearchAgent OrchestratorBun Core APIUserSafety PolicyModalFood SearchAgent OrchestratorBun Core APIUser#chatgpt-mermaid-\_r_11p\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_11p\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_11p\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_11p\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_11p\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_11p\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_11p\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_11p\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_11p\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_11p\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_11p\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_11p\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11p\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11p\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_11p\_ p{margin:0;}#chatgpt-mermaid-\_r_11p\_ .actor{stroke:rgb(31, 78, 148);fill:rgb(9, 23, 44);stroke-width:1;}#chatgpt-mermaid-\_r_11p\_ rect.actor.outer-path[data-look="neo"]{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11p\_ rect.note[data-look="neo"]{stroke:rgb(58, 132, 63);fill:rgb(48, 48, 48);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11p\_ text.actor>tspan{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_11p\_ .actor-line{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11p\_ .innerArc{stroke-width:1.5;stroke-dasharray:none;}#chatgpt-mermaid-\_r_11p\_ .messageLine0{stroke-width:1.5;stroke-dasharray:none;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11p\_ .messageLine1{stroke-width:1.5;stroke-dasharray:2,2;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11p\_ [id$="-arrowhead"] path{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11p\_ .sequenceNumber{fill:#505050;}#chatgpt-mermaid-\_r_11p\_ [id$="-sequencenumber"]{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11p\_ [id$="-crosshead"] path{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_11p\_ .messageText{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_11p\_ .labelBox{stroke:rgba(255, 255, 255, 0.15);fill:rgb(0, 0, 0);filter:none;}#chatgpt-mermaid-\_r_11p\_ .labelText,#chatgpt-mermaid-\_r_11p\_ .labelText>tspan{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_11p\_ .loopText,#chatgpt-mermaid-\_r_11p\_ .loopText>tspan{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_11p\_ .sectionTitle,#chatgpt-mermaid-\_r_11p\_ .sectionTitle>tspan{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_11p\_ .loopLine{stroke-width:2px;stroke-dasharray:2,2;stroke:rgba(255, 255, 255, 0.15);fill:rgba(255, 255, 255, 0.15);}#chatgpt-mermaid-\_r_11p\_ .note{stroke:rgb(58, 132, 63);fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_11p\_ .noteText,#chatgpt-mermaid-\_r_11p\_ .noteText>tspan{fill:rgb(237, 237, 237);stroke:none;font-weight:normal;}#chatgpt-mermaid-\_r_11p\_ .activation0{fill:rgb(48, 48, 48);stroke:hsl(0, 0%, 8.8235294118%);}#chatgpt-mermaid-\_r_11p\_ .activation1{fill:rgb(48, 48, 48);stroke:hsl(0, 0%, 8.8235294118%);}#chatgpt-mermaid-\_r_11p\_ .activation2{fill:rgb(48, 48, 48);stroke:hsl(0, 0%, 8.8235294118%);}#chatgpt-mermaid-\_r_11p\_ .actorPopupMenu{position:absolute;}#chatgpt-mermaid-\_r_11p\_ .actorPopupMenuPanel{position:absolute;fill:rgb(9, 23, 44);box-shadow:0px 8px 16px 0px rgba(0,0,0,0.2);filter:drop-shadow(3px 5px 2px rgb(0 0 0 / 0.4));}#chatgpt-mermaid-\_r_11p\_ .actor-man circle,#chatgpt-mermaid-\_r_11p\_ line{fill:rgb(9, 23, 44);stroke-width:2px;}#chatgpt-mermaid-\_r_11p\_ g rect.rect{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_11p\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_11p\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_11p\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_11p\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_11p\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11p\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_11p\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_11p\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Food and activity requestVerify session and consentIntent + permitted contextSearch appropriate food candidatesSource-linked food optionsRank candidate preferencesModel result and versionCheck food and activity optionsApproved options or restrictionsStructured recommendationOptions + reasoning + limitationsConfirm selected optionSave user-approved plan

Sistem idealnya melakukan:

1. Memahami bahwa pengguna membutuhkan bantuan makanan, biaya, dan perencanaan aktivitas.
2. Memeriksa preferensi, alergi, batasan kesehatan, serta informasi lain yang memang diperlukan dan telah diizinkan.
3. Mengambil kandidat makanan dengan sumber nutrisi.
4. Menentukan apakah diperlukan informasi porsi atau komposisi tambahan.
5. Menghasilkan alternatif yang kompatibel dengan anggaran dan preferensi.
6. Memeriksa apakah aktivitas yang diminta sesuai dengan eligibility dan batasan yang diketahui.
7. Menampilkan opsi, tingkat kepastian informasi, dan alasan pemilihan.
8. Menyimpan pilihan hanya setelah pengguna mengonfirmasi.

Semua rekomendasi aktivitas tetap dibatasi sebagai dukungan perencanaan gaya hidup, bukan penilaian bahwa aktivitas tersebut aman secara klinis untuk setiap keadaan.

# PART B — FOOD SEARCH & PERSONALIZED NUTRITION

## 9. Food Intelligence Engine

Tujuan Food Intelligence bukan sekadar memperlihatkan angka kalori, melainkan membantu pengguna memahami kandungan makanan, mencatat konsumsi secara praktis, dan memilih alternatif yang sesuai kebutuhan serta kebiasaan mereka.

[nasi pecel. vegetable with peanut sauce](https://images.openai.com/static-rsc-4/UXkx9oXKsJGjPsD8HCxOfqR9I4DQKGGahxGu7zhRWYC8rtSyDH4Iaffr5fRD93j2YubRcfUzD0N_8FImXWfMg3q9gzw_kT_x_cKqgXCSQz3VOCSPXTjMIW-6lb1WXqLsQ7lInhVOJGb5wR1chtvMV0uGni7XgQBJoSXpeIuNk9u12hMiG7p5u0Qa3xuQyvio?purpose=inline)

Local Food Discovery

Menemukan makanan lokal dan variasi komposisinya

[ScanFood.AI — Snap Your Food, Know Your Calories](https://images.openai.com/static-rsc-4/MFvX0Qd7YG4P0VCq6S-dcSmnWaPDqHlSsxt0qrUOmOjbGtvZ6LEwnLL1GI_EO16drGklnhC6YjTu5OjBpAjxBh9aNqSe4lNBx9ArKQK17SFhKv504gipeMkBMwjKdGcHCW6EdMhs0uxiKkXM2AA0Zc5FnwQ-4aN92m8xuD_cFgA?purpose=inline)

Smart Food Logging

Foto atau pencarian, dilanjutkan konfirmasi komposisi

### 9.1 Empat cara pengguna mencatat makanan

- Manual Search: mengetik nama makanan dan memilih hasil dari katalog.
- Food Photo: mengambil gambar, lalu model mengenali kandidat makanan yang perlu dikonfirmasi.
- Barcode Scan: mengambil label nutrisi produk kemasan melalui sumber produk yang sesuai.
- Quick Repeat: menggunakan kembali makanan atau resep yang pernah dicatat.

Keempat alur masuk ke sistem `meal_logs` dan `meal_items` existing, sehingga tidak perlu ada database makanan yang terpisah untuk setiap cara input.

### 9.2 Hybrid Food Search Pipeline

\#chatgpt-mermaid-\_r_12g\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_12g\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_12g\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_12g\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_12g\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_12g\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_12g\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_12g\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_12g\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_12g\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_12g\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_12g\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_12g\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_12g\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_12g\_ p{margin:0;}#chatgpt-mermaid-\_r_12g\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_12g\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_12g\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_12g\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_12g\_ .label text,#chatgpt-mermaid-\_r_12g\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_12g\_ .node rect,#chatgpt-mermaid-\_r_12g\_ .node circle,#chatgpt-mermaid-\_r_12g\_ .node ellipse,#chatgpt-mermaid-\_r_12g\_ .node polygon,#chatgpt-mermaid-\_r_12g\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_12g\_ .rough-node .label text,#chatgpt-mermaid-\_r_12g\_ .node .label text,#chatgpt-mermaid-\_r_12g\_ .image-shape .label,#chatgpt-mermaid-\_r_12g\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_12g\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_12g\_ .rough-node .label,#chatgpt-mermaid-\_r_12g\_ .node .label,#chatgpt-mermaid-\_r_12g\_ .image-shape .label,#chatgpt-mermaid-\_r_12g\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_12g\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_12g\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_12g\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_12g\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_12g\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_12g\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_12g\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_12g\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_12g\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_12g\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_12g\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_12g\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_12g\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_12g\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_12g\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_12g\_ .icon-shape,#chatgpt-mermaid-\_r_12g\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_12g\_ .icon-shape p,#chatgpt-mermaid-\_r_12g\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_12g\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_12g\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_12g\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_12g\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_12g\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_12g\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_12g\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_12g\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_12g\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_12g\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_12g\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_12g\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_12g\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_12g\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_12g\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_12g\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_12g\_ .node rect,#chatgpt-mermaid-\_r_12g\_ .node circle,#chatgpt-mermaid-\_r_12g\_ .node ellipse,#chatgpt-mermaid-\_r_12g\_ .node polygon,#chatgpt-mermaid-\_r_12g\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_12g\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_12g\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_12g\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_12g\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_12g\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Text / Photo / BarcodeInput Type?Food Recognition on ModalNormalize Name, Ingredientsand PreparationVerified Catalog Match?Existing Food CatalogCurated Nutrition SourcesExternal Structured Food APIsAgent Web Search FallbackCandidate Matching andSource RankingSufficient Evidence?Ask User to ClarifyPortion & IngredientConfirmationDeterministic NutritionCalculatorImmutable Nutrition SnapshotExisting Meal APIPhotoText / BarcodeYesNoMissingNoYes

### 9.3 Sumber nutrisi

Prioritas sumber sebaiknya bertingkat.

| Priority | Data source                               | Peran                                           |
| -------- | ----------------------------------------- | ----------------------------------------------- |
| 1        | Verified beOkay Food Catalog              | Hasil cepat dan konsisten                       |
| 2        | Kemenkes Tabel Komposisi Pangan Indonesia | Rujukan komposisi pangan lokal                  |
| 3        | USDA FoodData Central                     | Referensi nutrisi terstruktur                   |
| 4        | Open Food Facts                           | Produk kemasan, barcode, dan label              |
| 5        | Search Engine API                         | Menemukan sumber ketika katalog belum mencukupi |

Kemenkes memiliki publikasi [Tabel Komposisi Pangan Indonesia (2020)](https://repository.kemkes.go.id/book/668?utm_source=chatgpt.com). USDA menyediakan API pencarian dan detail komposisi makanan, sementara Open Food Facts memiliki API terbuka untuk data produk. Keduanya memerlukan evaluasi kelengkapan, kualitas, dan lisensi sebelum integrasi produksi.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://repository.kemkes.go.id\&sz=32)

Kemkes Repository+2



Search Engine Agent berfungsi sebagai discovery engine, bukan nutrition authority. Artikel internet yang menyebut sebuah makanan mengandung sejumlah kalori belum tentu membahas porsi, komposisi, atau cara memasak yang sama.

Hasil web juga harus melewati content sanitization, source verification, allowlist bila sesuai, pembatasan domain, serta proteksi prompt injection sebelum digunakan agent.

### 9.4 Nutrition calculation

Setelah nutrient density dan gram terkonfirmasi:

\\[ N_i=\frac{w_i}{100}n\_{i,100g} \\]

\\[ N\_{\text{meal}}=\sum_i N_i \\]

Dengan \\(w_i\\) sebagai berat masing-masing komponen dan \\(n\_{i,100g}\\) sebagai nilai nutrisi per 100 gram.

Lakukan kalkulasi secara deterministik menggunakan Decimal, bukan menjumlahkan nilai melalui LLM.

Sistem wajib mempertahankan status:

- `COMPLETE`: semua komponen yang diperlukan memiliki nilai yang layak.
- `PARTIAL`: hanya sebagian komponen diketahui.
- `UNKNOWN`: tidak ada informasi memadai untuk menghitung total.
- `NEEDS_REVIEW`: nilai atau sumber membutuhkan koreksi.

Nilai `PARTIAL` tidak boleh diberi label sebagai total energi seluruh makanan. Unknown bukan nol.

### 9.5 Food Search Result Contract

Contoh output terstruktur:

```

{
  "query": "nasi pecel",
  "status": "NEEDS_PORTION_CONFIRMATION",
  "candidates": [
    {
      "food_name": "Nasi pecel",
      "match_type": "COMPOSITE_DISH",
      "components": [
        "rice",
        "vegetables",
        "peanut_sauce"
      ],
      "portion": {
        "grams": null,
        "confirmed": false
      },
      "nutrition": {
        "energy_kcal": null,
        "carbohydrates_g": null,
        "protein_g": null,
        "fat_g": null
      },
      "evidence_status": "PARTIAL",
      "source_refs": []
    }
  ],
  "next_action": "ASK_FOR_COMPONENTS_AND_PORTION"
}

```

Output ini sengaja tidak mengarang angka kalori. Setelah sumber dan porsi valid, sistem dapat menghasilkan nutrient snapshot, menyimpan versi sumber, serta mencatatnya ke Nutrition API yang sudah ada.

### 9.6 Personalized Meal Planning

Food Search dan Meal Planning merupakan dua kemampuan berbeda.

Food Search menjawab: "Makanan ini mengandung apa?"

Meal Planning menjawab: "Di antara pilihan makanan yang tersedia, opsi mana paling sesuai dengan preferensi dan batasan yang diketahui?"

Parameter perencanaan:

| Domain         | Data yang digunakan                                                            |
| -------------- | ------------------------------------------------------------------------------ |
| Health context | Segmen pengguna, kondisi/batasan yang dilaporkan atau diverifikasi sesuai izin |
| Nutrition      | Kandungan dan porsi yang memiliki sumber                                       |
| Preference     | Makanan favorit, alergi, pantangan, selera                                     |
| Budget         | Anggaran per makan atau per hari                                               |
| Availability   | Makanan dan bahan yang realistis tersedia                                      |
| Schedule       | Waktu makan dan aktivitas                                                      |
| History        | Pilihan sebelumnya dan feedback                                                |

Urutan pengambilan keputusan:

1. Filter alergi, pantangan, dan constraint keselamatan.
2. Seleksi kandidat yang memiliki komposisi nutrisi memadai.
3. Sesuaikan preferensi makanan, budaya, dan anggaran.
4. Rangking opsi menggunakan rules atau model yang tervalidasi.
5. Sajikan alasan serta bagian data yang belum pasti.
6. Pengguna memilih menu atau memodifikasinya.

Rencana makanan bukan resep medis otomatis. Jika kebutuhan nutrisi spesifik belum ditetapkan secara sah, sistem tidak boleh mengarang target energi atau karbohidrat pribadi.

# PART C — MODAL ML INFERENCE

## 10. ML model deployment architecture

Kita menggunakan Modal khusus sebagai inference infrastructure.

Model dapat dibangun dan dievaluasi pada pipeline riset tersendiri, kemudian versi yang telah disetujui dideploy ke Modal. Model yang sedang dievaluasi tidak otomatis menjadi model produksi.

\#chatgpt-mermaid-\_r_136\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_136\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_136\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_136\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_136\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_136\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_136\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_136\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_136\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_136\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_136\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_136\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_136\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_136\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_136\_ p{margin:0;}#chatgpt-mermaid-\_r_136\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_136\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_136\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_136\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_136\_ .label text,#chatgpt-mermaid-\_r_136\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_136\_ .node rect,#chatgpt-mermaid-\_r_136\_ .node circle,#chatgpt-mermaid-\_r_136\_ .node ellipse,#chatgpt-mermaid-\_r_136\_ .node polygon,#chatgpt-mermaid-\_r_136\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_136\_ .rough-node .label text,#chatgpt-mermaid-\_r_136\_ .node .label text,#chatgpt-mermaid-\_r_136\_ .image-shape .label,#chatgpt-mermaid-\_r_136\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_136\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_136\_ .rough-node .label,#chatgpt-mermaid-\_r_136\_ .node .label,#chatgpt-mermaid-\_r_136\_ .image-shape .label,#chatgpt-mermaid-\_r_136\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_136\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_136\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_136\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_136\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_136\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_136\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_136\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_136\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_136\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_136\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_136\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_136\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_136\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_136\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_136\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_136\_ .icon-shape,#chatgpt-mermaid-\_r_136\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_136\_ .icon-shape p,#chatgpt-mermaid-\_r_136\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_136\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_136\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_136\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_136\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_136\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_136\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_136\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_136\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_136\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_136\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_136\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_136\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_136\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_136\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_136\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_136\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_136\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_136\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_136\_ .node rect,#chatgpt-mermaid-\_r_136\_ .node circle,#chatgpt-mermaid-\_r_136\_ .node ellipse,#chatgpt-mermaid-\_r_136\_ .node polygon,#chatgpt-mermaid-\_r_136\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_136\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_136\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_136\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_136\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_136\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Consented / ApprovedTraining DataData Preparation & LeakageChecksModel TrainingEvaluation & CalibrationModel RegistryDeploy Model to ModalAuthenticated InferenceEndpointAgent ML ClientPrediction ValidationSafety GateEligible User-facingExplanationRules / No PredictionPassFailAllowedBlocked

Dokumentasi Modal mendukung endpoint HTTP menggunakan `@modal.fastapi_endpoint` dan deployment aplikasi melalui `modal deploy`. Untuk endpoint privat, autentikasi proxy harus dikonfigurasi sesuai metode yang didukung.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://modal.com\&sz=32)

Modal Docs+1



### 10.1 Model candidates dan prioritas

| Model                          | Tipe                             | Prioritas                                         |
| ------------------------------ | -------------------------------- | ------------------------------------------------- |
| Food Image Recognition         | Computer Vision                  | P1, jika dataset siap                             |
| Habit Adherence Prediction     | Classification                   | Research                                          |
| Meal Candidate Ranking         | Learning-to-Rank / ranking model | P2                                                |
| Activity Candidate Ranking     | Ranking / contextual model       | P2                                                |
| Longitudinal Behavior Patterns | Time-series analysis             | P2                                                |
| Glucose Forecasting            | Time-series prediction           | Research setelah kelayakan klinis                 |
| Clinical Risk Progression      | Clinical prediction              | Di luar MVP; memerlukan studi dan validasi khusus |

Jangan melatih model hanya karena fitur membutuhkan AI. Bila rule-based ranking memberikan hasil yang bisa dijelaskan dan mencukupi, kita sebaiknya menggunakannya terlebih dahulu.

### 10.2 Contoh API contract

```

{
  "request_id": "inference-001",
  "model_key": "habit_adherence",
  "model_version": "1.0.0",
  "feature_schema_version": "1.0",
  "features": {
    "activity_days_last_7": 3,
    "goal_completion_ratio_14d": 0.70,
    "logging_coverage_14d": 0.82,
    "preferred_activity": "walking"
  }
}

```

Response dari Modal:

```

{
  "request_id": "inference-001",
  "model_version": "1.0.0",
  "status": "SUCCESS",
  "prediction": {
    "score": 0.73
  },
  "calibration_status": "NOT_VALIDATED",
  "usage_policy": "RESEARCH_ONLY",
  "inference_ms": 135
}

```

Seluruh angkanya sintetis sebagai contoh schema. `RESEARCH_ONLY` berarti hasil tidak boleh digunakan sebagai rekomendasi kesehatan untuk pengguna.

### 10.3 Model governance

Setiap model harus memiliki informasi berikut:

| Field                    | Keterangan                          |
| ------------------------ | ----------------------------------- |
| Model version            | Versi artefak yang immutable        |
| Feature schema version   | Definisi dan satuan input           |
| Training data provenance | Sumber dan izin penggunaan data     |
| Intended population      | Populasi tempat model dievaluasi    |
| Validation metrics       | Evaluasi sesuai problem             |
| Calibration              | Kesesuaian probabilitas prediksi    |
| Known limitations        | Batasan penggunaan                  |
| Approval status          | Research, shadow, approved, retired |
| Rollback version         | Versi aman sebelumnya               |

Khusus model prediksi perilaku, jangan hanya menggunakan accuracy. Periksa calibration, precision/recall yang relevan, stratified performance, dan out-of-distribution behavior.

Untuk ranking makanan dan aktivitas, gunakan metrik seperti NDCG\@K, acceptance rate, serta evaluasi apakah rekomendasi tidak melanggar constraint yang ditentukan.

### 10.4 Fallback design

Jika Modal timeout, cold-start, tidak tersedia, atau model versi yang diminta tidak ditemukan, aplikasi tetap harus bekerja.

Food logging tetap menggunakan database dan kalkulasi deterministik. Activity logging tetap tersedia. Personalized ranking dapat kembali menggunakan rules yang telah ditinjau.

AI bukan satu-satunya jalan untuk menyimpan makanan atau olahraga.

# PART D — WEARABLE & ADAPTIVE ACTIVITY

## 11. Integrasi jam pintar

Untuk Android, integrasi awal paling masuk akal adalah Health Connect. Untuk iOS, gunakan HealthKit. Keduanya memerlukan izin data sesuai platform dan hanya bisa membaca data yang benar-benar tersedia dari sumber yang kompatibel.

Health Connect mendukung exercise sessions dan metrik workout seperti heart rate, jarak, serta rute dengan persyaratan permission dan background execution tertentu.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developer.android.com\&sz=32)

Android Developers+1



### 11.1 Wearable data flow

InsightsEvent WorkerPostgreSQLBun APIFlutterHealth PlatformSmartwatchInsightsEvent WorkerPostgreSQLBun APIFlutterHealth PlatformSmartwatch#chatgpt-mermaid-\_r_142\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_142\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_142\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_142\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_142\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_142\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_142\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_142\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_142\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_142\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_142\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_142\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_142\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_142\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_142\_ p{margin:0;}#chatgpt-mermaid-\_r_142\_ .actor{stroke:rgb(31, 78, 148);fill:rgb(9, 23, 44);stroke-width:1;}#chatgpt-mermaid-\_r_142\_ rect.actor.outer-path[data-look="neo"]{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_142\_ rect.note[data-look="neo"]{stroke:rgb(58, 132, 63);fill:rgb(48, 48, 48);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_142\_ text.actor>tspan{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_142\_ .actor-line{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_142\_ .innerArc{stroke-width:1.5;stroke-dasharray:none;}#chatgpt-mermaid-\_r_142\_ .messageLine0{stroke-width:1.5;stroke-dasharray:none;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_142\_ .messageLine1{stroke-width:1.5;stroke-dasharray:2,2;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_142\_ [id$="-arrowhead"] path{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_142\_ .sequenceNumber{fill:#505050;}#chatgpt-mermaid-\_r_142\_ [id$="-sequencenumber"]{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_142\_ [id$="-crosshead"] path{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_142\_ .messageText{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_142\_ .labelBox{stroke:rgba(255, 255, 255, 0.15);fill:rgb(0, 0, 0);filter:none;}#chatgpt-mermaid-\_r_142\_ .labelText,#chatgpt-mermaid-\_r_142\_ .labelText>tspan{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_142\_ .loopText,#chatgpt-mermaid-\_r_142\_ .loopText>tspan{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_142\_ .sectionTitle,#chatgpt-mermaid-\_r_142\_ .sectionTitle>tspan{fill:rgb(237, 237, 237);stroke:none;}#chatgpt-mermaid-\_r_142\_ .loopLine{stroke-width:2px;stroke-dasharray:2,2;stroke:rgba(255, 255, 255, 0.15);fill:rgba(255, 255, 255, 0.15);}#chatgpt-mermaid-\_r_142\_ .note{stroke:rgb(58, 132, 63);fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_142\_ .noteText,#chatgpt-mermaid-\_r_142\_ .noteText>tspan{fill:rgb(237, 237, 237);stroke:none;font-weight:normal;}#chatgpt-mermaid-\_r_142\_ .activation0{fill:rgb(48, 48, 48);stroke:hsl(0, 0%, 8.8235294118%);}#chatgpt-mermaid-\_r_142\_ .activation1{fill:rgb(48, 48, 48);stroke:hsl(0, 0%, 8.8235294118%);}#chatgpt-mermaid-\_r_142\_ .activation2{fill:rgb(48, 48, 48);stroke:hsl(0, 0%, 8.8235294118%);}#chatgpt-mermaid-\_r_142\_ .actorPopupMenu{position:absolute;}#chatgpt-mermaid-\_r_142\_ .actorPopupMenuPanel{position:absolute;fill:rgb(9, 23, 44);box-shadow:0px 8px 16px 0px rgba(0,0,0,0.2);filter:drop-shadow(3px 5px 2px rgb(0 0 0 / 0.4));}#chatgpt-mermaid-\_r_142\_ .actor-man circle,#chatgpt-mermaid-\_r_142\_ line{fill:rgb(9, 23, 44);stroke-width:2px;}#chatgpt-mermaid-\_r_142\_ g rect.rect{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_142\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_142\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_142\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_142\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_142\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_142\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_142\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_142\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_142\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_142\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Recorded workoutAuthorized health recordsNormalize + deduplicate locallyImport records with source IDsCheck consent and source qualityPersist sessions and metricsImport statusSynced / Needs ReviewWorkoutImported eventRecompute activity summaryDerived summaryUpdated Today and Progress

Data yang diprioritaskan:

| Data             | Fungsi                                 |
| ---------------- | -------------------------------------- |
| Exercise session | Jenis dan durasi kegiatan              |
| Steps            | Aktivitas harian                       |
| Heart rate       | Metrik sesi yang tersedia              |
| Distance         | Jarak aktivitas                        |
| Sleep sessions   | Konteks kebiasaan, dengan izin         |
| Activity source  | Identifikasi perangkat/aplikasi sumber |
| Sync status      | Freshness dan kelengkapan data         |

Heart rate dari smartwatch tidak dapat menggantikan pengukuran glukosa, dan data langkah tidak cukup untuk memastikan suatu aktivitas aman.

### 11.2 Wearable data integrity

Perangkat yang sama dapat menghasilkan data melalui beberapa aplikasi. Sistem harus menghindari menghitung satu aktivitas berkali-kali.

Aturan dasar:

- Simpan `source_provider`, `source_record_id`, dan `device_reference` jika tersedia.
- Gunakan idempotent upsert untuk record sumber yang identik.
- Bedakan record duplikat dengan dua sumber yang benar-benar berbeda.
- Periksa overlap sesi sebagai kandidat review, bukan otomatis menghapus.
- Tetapkan precedence atau user confirmation saat data saling bertentangan.
- Simpan `recorded_at`, `observed_at`, dan `synced_at` sebagai waktu berbeda.
- Tandai data yang belum tersinkronisasi sebagai stale atau unavailable.

### 11.3 Adaptive Exercise Planner

Adaptive Exercise tidak berarti model bebas membuat latihan baru berdasarkan denyut jantung.

Prosesnya:

\#chatgpt-mermaid-\_r_149\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_149\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_149\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_149\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_149\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_149\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_149\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_149\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_149\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_149\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_149\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_149\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_149\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_149\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_149\_ p{margin:0;}#chatgpt-mermaid-\_r_149\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_149\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_149\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_149\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_149\_ .label text,#chatgpt-mermaid-\_r_149\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_149\_ .node rect,#chatgpt-mermaid-\_r_149\_ .node circle,#chatgpt-mermaid-\_r_149\_ .node ellipse,#chatgpt-mermaid-\_r_149\_ .node polygon,#chatgpt-mermaid-\_r_149\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_149\_ .rough-node .label text,#chatgpt-mermaid-\_r_149\_ .node .label text,#chatgpt-mermaid-\_r_149\_ .image-shape .label,#chatgpt-mermaid-\_r_149\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_149\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_149\_ .rough-node .label,#chatgpt-mermaid-\_r_149\_ .node .label,#chatgpt-mermaid-\_r_149\_ .image-shape .label,#chatgpt-mermaid-\_r_149\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_149\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_149\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_149\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_149\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_149\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_149\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_149\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_149\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_149\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_149\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_149\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_149\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_149\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_149\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_149\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_149\_ .icon-shape,#chatgpt-mermaid-\_r_149\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_149\_ .icon-shape p,#chatgpt-mermaid-\_r_149\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_149\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_149\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_149\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_149\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_149\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_149\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_149\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_149\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_149\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_149\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_149\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_149\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_149\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_149\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_149\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_149\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_149\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_149\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_149\_ .node rect,#chatgpt-mermaid-\_r_149\_ .node circle,#chatgpt-mermaid-\_r_149\_ .node ellipse,#chatgpt-mermaid-\_r_149\_ .node polygon,#chatgpt-mermaid-\_r_149\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_149\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_149\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_149\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_149\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_149\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Activity Preference + HealthContextPersonal Activity BaselineAllowed Activity CatalogEligibility / Safety RulesPreference-based RankingCandidate Activity PlanUser ChoosesManual or Wearable TrackingActivity + User FeedbackUpdate Personal BaselineEligibleNot Eligible

Rencana aktivitas memprioritaskan kemampuan dan preferensi, bukan mengejar jumlah kalori terbakar atau leaderboard.

Sistem dapat membantu menyusun pilihan berjalan kaki atau aktivitas lain yang sesuai dengan informasi yang tersedia. Bila pengguna melaporkan gejala, pembatasan dokter, atau risiko yang tidak dapat dievaluasi dengan aman, sistem tidak boleh meningkatkan aktivitas secara otomatis.

### 11.4 Behavior adaptation

Aku akan membedakan tiga hasil evaluasi:

Adherence: apakah aktivitas yang dipilih terlaksana?

Tolerance: bagaimana pengguna melaporkan pengalaman dan toleransinya?

Data coverage: seberapa lengkap catatan untuk dievaluasi?

Ketiganya tidak sama dengan clinical effectiveness. Pengguna yang menyelesaikan aktivitas tiga kali dalam seminggu belum tentu mengalami perbaikan glukosa, dan sistem tidak boleh mengklaim demikian tanpa bukti yang memadai.

# PART E — COMMUNITY & GAMIFICATION SYSTEM

## 12. Community architecture: Hyperlocal Healthy Communities

Community akan menjadi lapisan motivasi sosial, bukan bagian dari pengambilan keputusan medis.

Fungsinya membantu pengguna menemukan lingkungan pendukung, mengikuti tantangan kebiasaan, dan merasa bahwa mereka tidak menjalankan perubahan gaya hidup sendirian.

### 12.1 Community discovery

Pengguna dapat memilih wilayah komunitas berdasarkan kota/kabupaten atau kecamatan secara sukarela. Lokasi ini merupakan wilayah keanggotaan, bukan lokasi GPS real-time.

COMMUNITY SCREEN CONCEPT

## Healthy Together

Find support. Build habits. Grow together.

Komunitas Surabaya

Temukan aktivitas dan tantangan yang sesuai dengan kebiasaan yang ingin kamu bangun.

Walking Club

Aktivitas berjalan bersama secara sukarela

Healthy Meals

Ide makanan dan resep lokal

Habit Challenge

Tantangan konsistensi sesuai kemampuan

Leaderboard

Progres kebiasaan yang disetujui untuk ditampilkan

### 12.2 Desain privasi komunitas

Fitur "mengetahui penderita di sekitar" perlu diubah menjadi menemukan peserta komunitas yang secara eksplisit bersedia terlihat.

Pengguna tidak boleh dapat mencari daftar penderita diabetes di suatu wilayah, melihat titik rumah mereka, atau menyimpulkan diagnosis dari profil komunitas.

Setiap peserta menggunakan community alias yang terpisah dari identitas kesehatan. Keanggotaan, visibilitas profil, dan keikutsertaan leaderboard memiliki persetujuan yang berbeda.

Hal ini juga penting secara hukum: UU No. 27 Tahun 2022 menempatkan data dan informasi kesehatan sebagai data pribadi spesifik.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://jdih.komdigi.go.id\&sz=32)

JDIH Komdigi+1



### 12.3 Challenge Engine

Jenis tantangan yang bisa diimplementasikan:

| Challenge               | Progress metric                               | Prinsip                                         |
| ----------------------- | --------------------------------------------- | ----------------------------------------------- |
| Walking Consistency     | Hari tercapainya tujuan berjalan pribadi      | Tidak membandingkan jumlah langkah absolut      |
| Meal Logging Habit      | Konsistensi pencatatan sesuai target sukarela | Tidak memberi poin untuk makan lebih sedikit    |
| Weekly Activity         | Penyelesaian aktivitas yang dipilih           | Istirahat dan keterbatasan tidak dihukum        |
| Healthy Habit Check-in  | Refleksi dan penyelesaian micro-goals         | Pengguna mengonfirmasi sendiri                  |
| Community Participation | Keikutsertaan kegiatan sukarela               | Tidak mendorong oversharing informasi kesehatan |

### 12.4 Leaderboard Scoring

Leaderboard sebaiknya menggunakan personal goal normalized scoring.

Contoh formulasi awal:

\\[ S=0.5G+0.3C+0.2P \\]

Dengan:

- \\(G\\): tingkat penyelesaian tujuan pribadi yang telah ditetapkan dan layak.
- \\(C\\): konsistensi terhadap jadwal yang dipilih, dengan penanganan rest days.
- \\(P\\): partisipasi dalam challenge yang sesuai dan aman.

Ketiganya dinormalisasi pada skala 0–100. Formula perlu diuji terhadap fairness dan kemungkinan perilaku gaming sebelum digunakan secara nyata.

Yang tidak boleh menghasilkan poin adalah glukosa paling rendah, dosis obat, penurunan berat badan ekstrem, kalori makan paling sedikit, atau olahraga berlebihan.

Komunitas juga harus memiliki mekanisme moderasi, pelaporan, pemblokiran pengguna, penghapusan posting, dan penanganan informasi medis yang menyesatkan.

# PART F — DATA ARCHITECTURE & DATABASE

## 13. Database domain design

Kita mempertahankan PostgreSQL sebagai transactional source of truth dan Prisma sebagai ORM existing.

Perluasan database harus menjaga relasi domain, tetapi mencegah pencampuran data kesehatan dengan data sosial.

\#chatgpt-mermaid-\_r_15e\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_15e\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_15e\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_15e\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_15e\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15e\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_15e\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_15e\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_15e\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_15e\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_15e\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_15e\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15e\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15e\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_15e\_ p{margin:0;}#chatgpt-mermaid-\_r_15e\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15e\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15e\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15e\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_15e\_ .label text,#chatgpt-mermaid-\_r_15e\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15e\_ .node rect,#chatgpt-mermaid-\_r_15e\_ .node circle,#chatgpt-mermaid-\_r_15e\_ .node ellipse,#chatgpt-mermaid-\_r_15e\_ .node polygon,#chatgpt-mermaid-\_r_15e\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_15e\_ .rough-node .label text,#chatgpt-mermaid-\_r_15e\_ .node .label text,#chatgpt-mermaid-\_r_15e\_ .image-shape .label,#chatgpt-mermaid-\_r_15e\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_15e\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_15e\_ .rough-node .label,#chatgpt-mermaid-\_r_15e\_ .node .label,#chatgpt-mermaid-\_r_15e\_ .image-shape .label,#chatgpt-mermaid-\_r_15e\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_15e\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_15e\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15e\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15e\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_15e\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_15e\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_15e\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_15e\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_15e\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_15e\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_15e\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15e\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15e\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_15e\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15e\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_15e\_ .icon-shape,#chatgpt-mermaid-\_r_15e\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_15e\_ .icon-shape p,#chatgpt-mermaid-\_r_15e\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_15e\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_15e\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_15e\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_15e\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_15e\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_15e\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_15e\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_15e\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_15e\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15e\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_15e\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15e\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_15e\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_15e\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_15e\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_15e\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_15e\_ .node rect,#chatgpt-mermaid-\_r_15e\_ .node circle,#chatgpt-mermaid-\_r_15e\_ .node ellipse,#chatgpt-mermaid-\_r_15e\_ .node polygon,#chatgpt-mermaid-\_r_15e\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_15e\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_15e\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_15e\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_15e\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15e\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Privacy-Isolated CommunityIntelligence DomainPrivate Health DomainCommunity AliasMembershipsChallengesScore EventsLeaderboard SnapshotsFood Sources & EvidenceAgent RunsModel RegistryRecommendationsRecommendation FeedbackHealth ProfileGlucose ObservationsMeal LogsActivity SessionsMedication RecordsBehavior GoalsUser IdentitySeparate Opt-in

Diagram tersebut adalah domain map, bukan physical ERD final. Relasi, foreign key, dan constraints implementasi harus diturunkan dari data dictionary yang sudah ada serta kebutuhan baru.

## 14. Tabel existing yang digunakan kembali

| Tabel/domain           | Perluasan                                              |
| ---------------------- | ------------------------------------------------------ |
| `users`                | Tidak perlu digandakan                                 |
| `user_profiles`        | Preferensi dan konteks umum tetap milik core           |
| `health_profiles`      | Mendukung segmentation dan eligibility                 |
| `consent_records`      | Tambah purpose sesuai penggunaan AI/wearable/community |
| `food_catalog`         | Tautkan referensi eksternal yang telah divalidasi      |
| `meal_logs`            | Tetap menjadi kejadian konsumsi                        |
| `meal_items`           | Tetap menyimpan nutrition snapshot                     |
| `glucose_observations` | Pisahkan observasi dari prediksi                       |
| `activity_sessions`    | Tambah integrasi sumber wearable                       |
| `record_revisions`     | Koreksi historis tetap terlacak                        |
| `behavior_goals`       | Menjadi basis personal habit challenge                 |

Beberapa nama di atas berasal dari blueprint dan rencana P0. Status keberadaan fisiknya perlu dipastikan terhadap working tree terbaru sebelum membuat migrasi baru.

## 15. Tambahan entitas yang direkomendasikan

### 15.1 Nutrition Intelligence

| Tabel baru              | Fungsi                                      |
| ----------------------- | ------------------------------------------- |
| `food_source_records`   | Metadata sumber nutrisi dan versi referensi |
| `food_search_runs`      | Riwayat pencarian dan status penyelesaian   |
| `food_match_candidates` | Kandidat hasil pencocokan                   |
| `food_evidence_refs`    | Evidence yang mendukung nilai nutrisi       |
| `food_media_assets`     | Referensi foto makanan                      |
| `nutrition_preferences` | Preferensi, alergi, pantangan, anggaran     |
| `meal_plan_candidates`  | Kandidat meal plan                          |
| `meal_plan_feedback`    | Accepted, rejected, modified                |

Tidak perlu menyalin seluruh konten hasil web ke database. Simpan hanya data yang secara hukum boleh digunakan, dengan source URL, versi, unit, dan attribution jika diperlukan.

### 15.2 Wearable Intelligence

| Tabel baru                | Fungsi                            |
| ------------------------- | --------------------------------- |
| `wearable_connections`    | Sumber data dan status izin       |
| `wearable_sync_cursors`   | Incremental synchronization       |
| `wearable_observations`   | Metrik perangkat yang terstruktur |
| `workout_metrics`         | Agregat suatu workout             |
| `wearable_import_batches` | Audit import, retry, dan error    |

### 15.3 AI Operations

| Tabel baru                        | Fungsi                                      |
| --------------------------------- | ------------------------------------------- |
| `agent_runs`                      | Lifecycle eksekusi                          |
| `agent_tool_calls`                | Tool usage dan hasil tanpa menyimpan secret |
| `agent_evidence_refs`             | Referensi evidence yang digunakan           |
| `model_versions`                  | Registry model                              |
| `feature_snapshots`               | Input model yang berversi                   |
| `ml_inference_runs`               | Hasil inference, model version, latency     |
| `recommendation_candidates`       | Kandidat hasil sistem                       |
| `recommendation_safety_decisions` | Approve, block, review                      |
| `recommendation_feedback`         | Respons dan outcome pengguna                |

### 15.4 Community

| Tabel baru               | Fungsi                            |
| ------------------------ | --------------------------------- |
| `community_regions`      | Kode wilayah, tingkat wilayah     |
| `communities`            | Identitas kelompok                |
| `community_profiles`     | Alias dan preferensi visibilitas  |
| `community_memberships`  | Status keanggotaan                |
| `habit_challenges`       | Konfigurasi tantangan             |
| `challenge_participants` | Peserta yang menyetujui tantangan |
| `score_events`           | Ledger poin yang dapat diaudit    |
| `leaderboard_snapshots`  | Materialized ranking              |
| `community_reports`      | Moderasi konten/peserta           |
| `community_blocks`       | Kontrol interaksi antaranggota    |

### 15.5 Data access boundary

Jangan memberikan akses SQL langsung kepada agent atau Community Engine.

Service kesehatan memeriksa owner berdasarkan authenticated session. Agent meminta scoped context melalui service internal. Community Engine hanya memperoleh informasi challenge yang boleh dibagikan atau agregat yang telah diizinkan.

Data yang dihapus, dikoreksi, atau ditarik persetujuannya harus memicu invalidasi summary, personalisasi, dan konten turunan yang bergantung padanya.

# PART G — API DESIGN & EVENT WORKFLOWS

## 16. API contract

Rute yang sudah ada harus dipertahankan. Endpoint berikut merupakan tambahan yang diusulkan; tidak semuanya sudah diimplementasikan.

| Method | Endpoint                               | Purpose                                 |
| ------ | -------------------------------------- | --------------------------------------- |
| `GET`  | `/api/me/today`                        | Dashboard gabungan existing             |
| `GET`  | `/api/foods/search`                    | Pencarian katalog existing              |
| `POST` | `/api/me/meals`                        | Pencatatan meal existing                |
| `POST` | `/api/me/food-discovery`               | Memulai intelligent food search         |
| `GET`  | `/api/me/food-discovery/:id`           | Hasil kandidat dan evidence             |
| `POST` | `/api/me/meal-plans`                   | Membuat opsi meal plan                  |
| `POST` | `/api/me/activity-plans`               | Membuat opsi activity plan              |
| `POST` | `/api/me/agent/runs`                   | Memulai agent workflow                  |
| `GET`  | `/api/me/agent/runs/:id/events`        | Streaming status dan hasil              |
| `POST` | `/api/me/wearable-imports`             | Import data wearable                    |
| `GET`  | `/api/me/recommendations`              | Rekomendasi yang tersedia               |
| `POST` | `/api/me/recommendations/:id/feedback` | Feedback atas rekomendasi               |
| `GET`  | `/api/communities`                     | Discovery komunitas                     |
| `POST` | `/api/me/community-memberships`        | Keanggotaan opt-in                      |
| `GET`  | `/api/challenges`                      | Challenge discovery                     |
| `POST` | `/api/challenges/:id/join`             | Keikutsertaan challenge                 |
| `GET`  | `/api/leaderboards/:regionId`          | Ranking yang telah diperiksa privasinya |

Untuk endpoint yang mengubah data, gunakan idempotency key atau operation ID stabil, terutama pada kondisi jaringan mobile yang tidak pasti.

API tidak boleh mempercayai `user_id` dari body sebagai identitas pemilik. Ownership, consent, dan permission harus dihitung di server.

## 17. Event-driven processing

| Event                         | Trigger                         | Consumer                      |
| ----------------------------- | ------------------------------- | ----------------------------- |
| `meal.recorded.v1`            | Pengguna menyimpan meal         | Nutrition summary             |
| `meal.corrected.v1`           | Koreksi makanan                 | Summary invalidation          |
| `glucose.observed.v1`         | Observasi glukosa baru          | Glucose summary               |
| `activity.imported.v1`        | Import wearable                 | Activity aggregate            |
| `goal.checked_in.v1`          | Konfirmasi tujuan               | Goal progress                 |
| `recommendation.responded.v1` | Feedback pengguna               | Personalization feedback      |
| `challenge.progressed.v1`     | Progres challenge terverifikasi | Scoring engine                |
| `consent.withdrawn.v1`        | Penarikan izin                  | Invalidation & access control |
| `model.deactivated.v1`        | Model ditarik                   | Disable inference / fallback  |

Semua event diproses secara at-least-once, dengan idempotent consumer. Jangan mengasumsikan event hanya pernah dikirim sekali.

Khusus scoring, catatan yang dikoreksi atau dibatalkan harus dapat menghasilkan penyesuaian poin, bukan membiarkan poin lama tetap ada selamanya.

# PART H — UI/UX & USER EXPERIENCE

## 18. Information architecture

Saran awal: pertahankan empat navigasi utama dari blueprint sebelumnya dan jadikan Community sebagai destination sekunder yang jelas dari Today atau Profile.

\#chatgpt-mermaid-\_r_15u\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_15u\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_15u\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_15u\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_15u\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15u\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_15u\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_15u\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_15u\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_15u\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_15u\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_15u\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15u\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15u\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_15u\_ p{margin:0;}#chatgpt-mermaid-\_r_15u\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15u\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15u\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15u\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_15u\_ .label text,#chatgpt-mermaid-\_r_15u\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15u\_ .node rect,#chatgpt-mermaid-\_r_15u\_ .node circle,#chatgpt-mermaid-\_r_15u\_ .node ellipse,#chatgpt-mermaid-\_r_15u\_ .node polygon,#chatgpt-mermaid-\_r_15u\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_15u\_ .rough-node .label text,#chatgpt-mermaid-\_r_15u\_ .node .label text,#chatgpt-mermaid-\_r_15u\_ .image-shape .label,#chatgpt-mermaid-\_r_15u\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_15u\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_15u\_ .rough-node .label,#chatgpt-mermaid-\_r_15u\_ .node .label,#chatgpt-mermaid-\_r_15u\_ .image-shape .label,#chatgpt-mermaid-\_r_15u\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_15u\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_15u\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15u\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15u\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_15u\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_15u\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_15u\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_15u\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_15u\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_15u\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_15u\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15u\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15u\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_15u\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_15u\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_15u\_ .icon-shape,#chatgpt-mermaid-\_r_15u\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_15u\_ .icon-shape p,#chatgpt-mermaid-\_r_15u\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_15u\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_15u\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_15u\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_15u\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_15u\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_15u\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_15u\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_15u\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_15u\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15u\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_15u\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_15u\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_15u\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_15u\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_15u\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_15u\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_15u\_ .node rect,#chatgpt-mermaid-\_r_15u\_ .node circle,#chatgpt-mermaid-\_r_15u\_ .node ellipse,#chatgpt-mermaid-\_r_15u\_ .node polygon,#chatgpt-mermaid-\_r_15u\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_15u\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_15u\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_15u\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_15u\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_15u\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}beOkay MobileOnboardingTodayLogInsightsProfileConsent & Health ContextPersonal Action PlanQuick RecordCommunityUnified TimelineLog FoodLog GlucoseLog ActivityWeekly ReviewEvidence DetailAI CoachChallengesLeaderboardConnected DevicesPrivacy Controls

Jika community engagement terbukti sangat sering digunakan, navigasi dapat dievaluasi kembali menjadi lima tab. Tetapi jangan langsung menambah navigasi hanya karena domain baru tersedia.

### 18.1 Today

Harus mampu menjawab pertanyaan:

- Apa yang telah tercatat hari ini?
- Apa tujuan kebiasaan aktifku?
- Apa langkah berikutnya yang aku pilih?
- Apakah data smartwatch sudah tersinkronisasi?
- Insight apa yang cukup didukung oleh data?
- Apakah ada challenge yang aku ikuti?

### 18.2 Food Intelligence

Layar berisi search, barcode/photo entry, daftar kandidat makanan, detail sumber, konfirmasi porsi, nutrisi, serta alternatif menu.

Tampilkan state seperti `SEARCHING`, `NEEDS_PORTION`, `PARTIAL`, `READY`, dan `ERROR`. Jangan mengisi angka sementara sebagai fakta.

### 18.3 Activity & Wearable

Layar berisi activity plan, histori, jenis olahraga, status perangkat, data terakhir, serta progress goals.

Tampilkan label sumber seperti `Manual`, `Imported`, dan `Needs Review`, sehingga pengguna memahami dari mana catatan berasal.

### 18.4 AI Coach

Chat merupakan satu pintu masuk, bukan satu-satunya cara menggunakan aplikasi.

AI Coach perlu bisa membuka kartu rekomendasi terstruktur yang memiliki alasan, sumber, status safety, dan aksi konfirmasi.

Respons "aku belum memiliki data cukup" merupakan keluaran yang benar dan tidak perlu disembunyikan.

### 18.5 Community

Layar berisi komunitas yang diikuti, wilayah pilihan, challenges, activity feed terbatas, leaderboard, dan privacy settings.

Hindari mekanisme feed tak berujung yang memprioritaskan engagement di atas kesehatan dan kenyamanan pengguna.

### 18.6 UI state contract

| State                | Behavior                              |
| -------------------- | ------------------------------------- |
| `EMPTY`              | Menjelaskan belum ada data            |
| `SAVED_LOCAL`        | Catatan tersimpan aman di perangkat   |
| `SYNCING`            | Menandakan sinkronisasi               |
| `SYNC_FAILED`        | Retry tanpa kehilangan data           |
| `CONFLICT`           | Pengguna dapat meninjau perubahan     |
| `INSUFFICIENT_DATA`  | Tidak membuat insight palsu           |
| `STALE`              | Memberi tahu hasil belum diperbarui   |
| `NEEDS_CONFIRMATION` | Meminta konfirmasi data atau tindakan |
| `SAFETY_BLOCKED`     | Menjelaskan batasan secara tepat      |
| `READY`              | Hasil siap digunakan sesuai cakupan   |

Gunakan desain calm health interface yang sudah menjadi arah proyek: tipografi Inter, hierarki jelas, kartu rapi, spacing lapang, bahasa Indonesia yang mudah dipahami, dan warna yang tidak menjadikan kadar glukosa sebagai skor prestasi.

# PART I — END-TO-END USER JOURNEY

## 19. User journey dari awal sampai personalisasi

1. Account Creation & Consent

   Pengguna mendaftar melalui Better Auth, menyelesaikan verifikasi, membaca tujuan pemrosesan data, dan memberikan consent sesuai kebutuhan. Izin wearable, AI analysis, dan community visibility terpisah.
2. Health & Lifestyle Onboarding

   Pengguna mengisi profil yang diperlukan: status kesehatan yang dilaporkan atau diverifikasi, preferensi makanan, alergi, aktivitas yang disukai, kemampuan, jadwal, serta tujuan pribadi. Field yang tidak perlu tidak dikumpulkan.
3. Baseline Collection

   Pengguna melakukan logging makanan, aktivitas, dan glukosa bila tersedia. Sistem menyediakan descriptive summaries, tetapi belum memaksakan personalized ML sebelum data memadai.
4. Intelligent Food Logging

   Pengguna mencari makanan atau mengambil foto. Food Search Agent mencari data nutrisi; pengguna mengonfirmasi komponen dan porsi; server menghitung dan menyimpan snapshot.
5. Activity Planning

   Sistem menawarkan pilihan aktivitas sesuai informasi yang diketahui. Pengguna memilih dan mengonfirmasi rencana. Jika menggunakan smartwatch, hasil workout dapat diimpor.
6. Personalized Insights

   Setelah data mencukupi, agent mengambil hasil analitik, referensi, dan jika sesuai model yang tervalidasi melalui Modal. Safety gate menentukan apakah saran dapat disampaikan.
7. Habit Intervention

   Pengguna memilih micro-goal, misalnya menjaga konsistensi aktivitas yang sudah sesuai. Reminders dapat digunakan jika disetujui, dengan quiet hours dan opsi berhenti.
8. Community Participation

   Pengguna dapat memilih komunitas wilayah dan tantangan. Data yang terlihat peserta lain hanya informasi yang disetujui dan memang boleh dibagikan.
9. Weekly Review & Adaptation

   Sistem mengevaluasi keterlaksanaan tujuan, kelengkapan data, feedback, dan pola yang teramati. Rencana berikutnya disesuaikan secara terkendali.

### 19.1 Closed-loop behavioral intelligence

\#chatgpt-mermaid-\_r_166\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_166\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_166\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_166\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_166\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_166\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_166\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_166\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_166\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_166\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_166\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_166\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_166\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_166\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_166\_ p{margin:0;}#chatgpt-mermaid-\_r_166\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_166\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_166\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_166\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_166\_ .label text,#chatgpt-mermaid-\_r_166\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_166\_ .node rect,#chatgpt-mermaid-\_r_166\_ .node circle,#chatgpt-mermaid-\_r_166\_ .node ellipse,#chatgpt-mermaid-\_r_166\_ .node polygon,#chatgpt-mermaid-\_r_166\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_166\_ .rough-node .label text,#chatgpt-mermaid-\_r_166\_ .node .label text,#chatgpt-mermaid-\_r_166\_ .image-shape .label,#chatgpt-mermaid-\_r_166\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_166\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_166\_ .rough-node .label,#chatgpt-mermaid-\_r_166\_ .node .label,#chatgpt-mermaid-\_r_166\_ .image-shape .label,#chatgpt-mermaid-\_r_166\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_166\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_166\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_166\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_166\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_166\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_166\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_166\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_166\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_166\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_166\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_166\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_166\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_166\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_166\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_166\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_166\_ .icon-shape,#chatgpt-mermaid-\_r_166\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_166\_ .icon-shape p,#chatgpt-mermaid-\_r_166\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_166\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_166\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_166\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_166\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_166\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_166\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_166\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_166\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_166\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_166\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_166\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_166\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_166\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_166\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_166\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_166\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_166\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_166\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_166\_ .node rect,#chatgpt-mermaid-\_r_166\_ .node circle,#chatgpt-mermaid-\_r_166\_ .node ellipse,#chatgpt-mermaid-\_r_166\_ .node polygon,#chatgpt-mermaid-\_r_166\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_166\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_166\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_166\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_166\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_166\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}ObserveUnderstandSuggest OptionsUser ChoosesActMeasure & ReviewEnough Evidence?Adapt Next PlanContinue ObservationYesNo

Ini adalah core innovation yang harus kamu buktikan.

Sistem tidak hanya menghasilkan rekomendasi sekali, lalu selesai. Ia mengingat preferensi yang diizinkan, mengevaluasi apa yang benar-benar terlaksana, serta menyesuaikan pilihan berikutnya tanpa mengabaikan keselamatan.

Penyesuaian tidak berarti langsung melakukan online learning setiap kali ada data baru. Untuk awal, gunakan rules dan pembaruan baseline. Model adaptif yang belajar dari interaksi pengguna baru diaktifkan setelah tersedia evaluasi yang memadai.

# PART J — SECURITY, PRIVACY & CLINICAL SAFETY

## 20. Security and safety architecture

Karena proyek menangani data kesehatan, kepercayaan harus menjadi bagian arsitektur, bukan fitur tambahan.

### 20.1 Consent scopes

Aku merekomendasikan pemisahan consent seperti:

| Consent                        | Purpose                           |
| ------------------------------ | --------------------------------- |
| `health_data_processing`       | Pencatatan kesehatan inti         |
| `descriptive_summaries`        | Ringkasan dan insight deskriptif  |
| `personalized_ai`              | Analisis personal oleh layanan AI |
| `wearable_import`              | Sinkronisasi perangkat            |
| `community_membership`         | Keanggotaan komunitas             |
| `community_profile_visibility` | Informasi profil yang dibagikan   |
| `challenge_leaderboard`        | Partisipasi ranking sukarela      |
| `research_data_use`            | Riset dengan persetujuan terpisah |

Nama-nama tersebut merupakan proposed scopes. Jangan mengubah consent policy existing tanpa memeriksa kompatibilitas dan melakukan tinjauan legal.

### 20.2 Clinical safety boundaries

Safety Engine memeriksa jenis permintaan, eligibility, kelengkapan data, red flags, validitas model, serta apakah rekomendasi membutuhkan clinical review.

Sebagai contoh, jika pengguna meminta perubahan dosis obat, agent harus menolak melakukan perubahan otomatis dan mengarahkan pengguna untuk membahasnya dengan tenaga kesehatan.

Jika data aktivitas dari jam terlambat masuk, sistem tidak boleh menganggap pengguna sama sekali tidak bergerak.

Jika nilai glukosa belum tersedia, sistem tidak boleh membuat prediksi glukosa berdasarkan jumlah langkah lalu menampilkannya sebagai pengukuran.

### 20.3 Privacy engineering

Persyaratan minimum:

- TLS untuk komunikasi dan enkripsi data sensitif saat disimpan.
- Authorization dan ownership checks pada seluruh endpoint kesehatan.
- Least-privilege service credentials.
- Pemisahan secret untuk development, staging, dan production.
- Audit trail untuk akses dan perubahan penting.
- Data minimization ketika memanggil agent, web search, dan Modal.
- Account-isolated offline storage.
- Data export dan deletion workflows.
- Consent withdrawal yang memblokir pemrosesan lanjutan yang tidak lagi diizinkan.
- Retention policy, incident response, dan review transfer data ke penyedia eksternal.

Pseudonimisasi bukan jaminan bahwa data tidak dapat diidentifikasi kembali. Karena itu, penggunaan Modal dan search API perlu dipetakan dalam data flow assessment, termasuk lokasi pemrosesan dan pihak penerima data.

# PART K — DEPLOYMENT & OPERATIONS

## 21. Deployment topology

Untuk tahap awal, beOkay tidak membutuhkan arsitektur microservices yang berlebihan.

\#chatgpt-mermaid-\_r_16d\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_16d\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_16d\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_16d\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_16d\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_16d\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_16d\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_16d\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_16d\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_16d\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_16d\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_16d\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_16d\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_16d\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_16d\_ p{margin:0;}#chatgpt-mermaid-\_r_16d\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_16d\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_16d\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_16d\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_16d\_ .label text,#chatgpt-mermaid-\_r_16d\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_16d\_ .node rect,#chatgpt-mermaid-\_r_16d\_ .node circle,#chatgpt-mermaid-\_r_16d\_ .node ellipse,#chatgpt-mermaid-\_r_16d\_ .node polygon,#chatgpt-mermaid-\_r_16d\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_16d\_ .rough-node .label text,#chatgpt-mermaid-\_r_16d\_ .node .label text,#chatgpt-mermaid-\_r_16d\_ .image-shape .label,#chatgpt-mermaid-\_r_16d\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_16d\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_16d\_ .rough-node .label,#chatgpt-mermaid-\_r_16d\_ .node .label,#chatgpt-mermaid-\_r_16d\_ .image-shape .label,#chatgpt-mermaid-\_r_16d\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_16d\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_16d\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_16d\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_16d\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_16d\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_16d\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_16d\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_16d\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_16d\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_16d\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_16d\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_16d\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_16d\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_16d\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_16d\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_16d\_ .icon-shape,#chatgpt-mermaid-\_r_16d\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_16d\_ .icon-shape p,#chatgpt-mermaid-\_r_16d\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_16d\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_16d\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_16d\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_16d\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_16d\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_16d\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_16d\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_16d\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_16d\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_16d\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_16d\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_16d\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_16d\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_16d\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_16d\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_16d\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_16d\_ .node rect,#chatgpt-mermaid-\_r_16d\_ .node circle,#chatgpt-mermaid-\_r_16d\_ .node ellipse,#chatgpt-mermaid-\_r_16d\_ .node polygon,#chatgpt-mermaid-\_r_16d\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_16d\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_16d\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_16d\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_16d\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_16d\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Flutter MobileTLS / Reverse ProxyBun Core APIPostgreSQLRedisBackground WorkerPython Agent ServicePrivate Object StorageModal ML EndpointsNutrition / Search APIsMetrics, Logs, Traces

### 21.1 Recommended stack

| Component     | Candidate technology                                    |
| ------------- | ------------------------------------------------------- |
| Mobile        | Flutter + Riverpod                                      |
| Core API      | Existing Bun.serve                                      |
| ORM           | Existing Prisma                                         |
| Database      | PostgreSQL                                              |
| Agent Service | Python + FastAPI + LangGraph                            |
| Model Serving | Modal                                                   |
| Queue         | Durable outbox + worker; Redis-backed queue bila perlu  |
| Cache         | Redis                                                   |
| Images        | Private S3-compatible storage                           |
| Search        | Food database adapters + search provider API            |
| Retrieval     | Curated references, PostgreSQL/pgvector bila diperlukan |
| Logging       | Structured logs + trace correlation                     |
| Monitoring    | OpenTelemetry-compatible metrics/tracing                |
| API Tests     | Bruno + Bun integration tests                           |
| Mobile Tests  | Flutter tests + Appium                                  |

PostgreSQL dan Redis dapat dijalankan sebagai layanan terkelola ketika dibutuhkan. Tidak perlu langsung menjalankan Kubernetes untuk MVP.

### 21.2 Scalability strategy

Skalabilitas harus difokuskan pada sumber beban yang nyata.

| Workload           | Strategy                                        |
| ------------------ | ----------------------------------------------- |
| Core tracking      | Indexed PostgreSQL queries                      |
| Food search        | Cache hasil pencarian yang aman digunakan ulang |
| Photo recognition  | Async model inference                           |
| Wearable imports   | Batched processing dan deduplication            |
| AI conversations   | Per-user rate limit dan tool budget             |
| Daily insights     | Scheduled/event-triggered recomputation         |
| Leaderboard        | Precomputed snapshots                           |
| Modal inference    | Independent scaling, batching jika sesuai       |
| User notifications | Scheduled jobs dengan consent checks            |

Setiap agent invocation sebaiknya memiliki batas biaya, waktu, jumlah tool calls, dan ukuran konteks. Kegagalan salah satu layanan eksternal tidak boleh membuat core tracking berhenti berfungsi.

# PART L — DEVELOPMENT ROADMAP

## 22. Urutan pengembangan dari repository existing

Urutan terbaik bukan langsung membangun semua agent sekaligus. Prioritaskan dependency yang menghasilkan data valid terlebih dahulu.

Phase 0

Audit & Complete Existing P0

Pastikan Medication, Goals, full timeline, full Insights, offline sync, consent, dan integrasi frontend benar-benar selesai dan teruji.

Phase 1

Food Intelligence

Bangun structured food adapters, search fallback, evidence validation, portion confirmation, dan integrasi Nutrition existing.

Phase 2

Wearable Foundation

Bangun Health Connect adapter, source normalization, idempotent import, activity summary, dan UI status koneksi.

Phase 3

Personal Planning & Rules

Bangun meal/activity candidate generation, eligibility rules, feedback, dan safety policy tanpa bergantung pada ML.

Phase 4

Hybrid Agentic + Modal

Implementasikan LangGraph orchestrator, tool registry, Modal inference client, RAG, guardrails, dan versioned outputs.

Phase 5

Community & Gamification

Bangun area selection, opt-in memberships, fair scoring, challenges, leaderboard, moderation, dan privacy testing.

Phase 6

Validation & Research

Laksanakan usability pilot, model evaluation, privacy review, safety review, dan pengujian dampak kebiasaan.

Phase 1 dan pekerjaan desain Community dapat berlangsung paralel, tetapi perubahan shared database dan API contracts harus dikoordinasikan agar tidak menimbulkan konflik.

### 22.1 Engineering deliverables per phase

Setiap phase harus menghasilkan artefak yang benar-benar dapat diperiksa:

| Deliverable                | Minimum requirement                           |
| -------------------------- | --------------------------------------------- |
| Architecture specification | Domain boundary, dependency map, data flow    |
| Data dictionary            | Fields, units, constraints, provenance        |
| API contract               | Request/response, errors, auth, idempotency   |
| UI specification           | Screens, states, accessibility, actions       |
| Implementation             | Backend, mobile, worker sesuai scope          |
| Tests                      | Unit, integration, negative, dan E2E relevan  |
| Observability              | Logs, metrics, traces, audit                  |
| Engineering report         | Apa yang selesai, bukti, apa yang belum       |
| Risk review                | Safety, privacy, reliability                  |
| Rollback plan              | Cara menonaktifkan fitur dan memulihkan versi |

Status `DONE` hanya diberikan jika acceptance criteria dan tes relevan benar-benar lulus.

## 23. Definition of Done untuk flagship capabilities

| Capability          | Acceptance criteria                                                               |
| ------------------- | --------------------------------------------------------------------------------- |
| Food Search         | Hasil dengan sumber, satuan, porsi, dan coverage; unknown tidak diisi nilai palsu |
| Nutrition Logging   | Source-linked snapshot tersimpan; koreksi tidak mengubah sejarah diam-diam        |
| Modal Integration   | Authenticated request, model version, timeout/fallback, input validation          |
| Agent Orchestration | Tool allowlist, consent, audit, bounded execution                                 |
| Adaptive Activity   | Tidak mengubah terapi; user approval; eligibility checks                          |
| Wearable Import     | Data terdeduplikasi, source traceable, permission withdrawal berfungsi            |
| Community Discovery | Hanya peserta opt-in, tanpa direktori diagnosis                                   |
| Leaderboard         | Fair scoring, tidak berbasis kondisi klinis, anti-abuse checks                    |
| Offline Tracking    | Data account-isolated, retry idempoten, conflict review                           |
| Insights            | Coverage dan limitation jelas, no unsupported causal claims                       |

## 24. Evaluation framework

Untuk memastikan sistem benar-benar menyelesaikan masalah, jangan hanya mengukur jumlah fitur atau kompleksitas agent.

| Product Usability    | Task completion, waktu pencatatan, error rate, usability score                   |
| -------------------- | -------------------------------------------------------------------------------- |
| Food Intelligence    | Food match precision, portion error, nutrient coverage, source validity          |
| Wearable Integration | Import success, duplicate rate, sync freshness, permission handling              |
| Agent Quality        | Task success, tool correctness, grounded explanation, safety violations, latency |
| ML Quality           | Task-specific metrics, calibration, drift, subgroup performance                  |
| Behavior Change      | Goal completion, habit consistency, voluntary retention, burden                  |
| Community            | Challenge participation, healthy engagement, fairness, reports                   |
| Security & Privacy   | Cross-account isolation, consent enforcement, unauthorized exposure tests        |

Untuk riset klinis, outcome seperti HbA1c, progresi prediabetes, atau risiko komplikasi memerlukan rancangan studi dan pengawasan yang sesuai. Pilot aplikasi singkat tidak dapat membuktikan klaim pencegahan penyakit.

## 25. Final System Synthesis

## beOkay: The Integrated Metabolic Behavior Loop

\#chatgpt-mermaid-\_r_17c\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237, 237, 237);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_17c\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_17c\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_17c\_ .error-icon{fill:rgb(48, 48, 48);}#chatgpt-mermaid-\_r_17c\_ .error-text{fill:rgb(237, 237, 237);stroke:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_17c\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_17c\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_17c\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_17c\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_17c\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_17c\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_17c\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_17c\_ .marker.cross{stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_17c\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_17c\_ p{margin:0;}#chatgpt-mermaid-\_r_17c\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_17c\_ .cluster-label text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_17c\_ .cluster-label span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_17c\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_17c\_ .label text,#chatgpt-mermaid-\_r_17c\_ span{fill:rgb(237, 237, 237);color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_17c\_ .node rect,#chatgpt-mermaid-\_r_17c\_ .node circle,#chatgpt-mermaid-\_r_17c\_ .node ellipse,#chatgpt-mermaid-\_r_17c\_ .node polygon,#chatgpt-mermaid-\_r_17c\_ .node path{fill:rgb(9, 23, 44);stroke:rgb(31, 78, 148);stroke-width:1px;}#chatgpt-mermaid-\_r_17c\_ .rough-node .label text,#chatgpt-mermaid-\_r_17c\_ .node .label text,#chatgpt-mermaid-\_r_17c\_ .image-shape .label,#chatgpt-mermaid-\_r_17c\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_17c\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_17c\_ .rough-node .label,#chatgpt-mermaid-\_r_17c\_ .node .label,#chatgpt-mermaid-\_r_17c\_ .image-shape .label,#chatgpt-mermaid-\_r_17c\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_17c\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_17c\_ .root .anchor path{fill:rgb(175, 175, 175)!important;stroke-width:0;stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_17c\_ .arrowheadPath{fill:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_17c\_ .edgePath .path{stroke:rgb(175, 175, 175);stroke-width:1px;}#chatgpt-mermaid-\_r_17c\_ .flowchart-link{stroke:rgb(175, 175, 175);fill:none;}#chatgpt-mermaid-\_r_17c\_ .edgeLabel{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_17c\_ .edgeLabel p{background-color:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_17c\_ .edgeLabel rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_17c\_ .labelBkg{background-color:rgba(0, 0, 0, 0.5);}#chatgpt-mermaid-\_r_17c\_ .cluster rect{fill:rgb(48, 48, 48);stroke:rgba(255, 255, 255, 0.15);stroke-width:1px;}#chatgpt-mermaid-\_r_17c\_ .cluster text{fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_17c\_ .cluster span{color:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_17c\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(48, 48, 48);border:1px solid rgba(255, 255, 255, 0.15);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_17c\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237, 237, 237);}#chatgpt-mermaid-\_r_17c\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_17c\_ .icon-shape,#chatgpt-mermaid-\_r_17c\_ .image-shape{background-color:rgb(0, 0, 0);text-align:center;}#chatgpt-mermaid-\_r_17c\_ .icon-shape p,#chatgpt-mermaid-\_r_17c\_ .image-shape p{background-color:rgb(0, 0, 0);padding:2px;}#chatgpt-mermaid-\_r_17c\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_17c\_ .image-shape .label rect{opacity:0.5;background-color:rgb(0, 0, 0);fill:rgb(0, 0, 0);}#chatgpt-mermaid-\_r_17c\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_17c\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_17c\_ .node .neo-node{stroke:rgb(31, 78, 148);}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_17c\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_17c\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].node .neo-line path{stroke:rgb(31, 78, 148);filter:none;}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_17c\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_17c\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_17c\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_17c\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_17c\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_17c\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(153, 206, 255);}#chatgpt-mermaid-\_r_17c\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_17c\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_17c\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-width:1px;}#chatgpt-mermaid-\_r_17c\_ .node rect,#chatgpt-mermaid-\_r_17c\_ .node circle,#chatgpt-mermaid-\_r_17c\_ .node ellipse,#chatgpt-mermaid-\_r_17c\_ .node polygon,#chatgpt-mermaid-\_r_17c\_ .node path{fill:rgb(0, 40, 77);stroke:rgba(255, 255, 255, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_17c\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_17c\_ .mermaid-decision .label-container{fill:rgb(0, 14, 26);stroke:rgb(26, 62, 95);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_17c\_ .edgePaths .flowchart-link{stroke:rgb(175, 175, 175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_17c\_ .marker{fill:rgb(175, 175, 175);stroke:rgb(175, 175, 175);}#chatgpt-mermaid-\_r_17c\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}PERSONHealth & Lifestyle DataFood IntelligenceWearable IntelligenceHybrid Agentic OrchestratorModal Personalized MLSafety & EvidencePersonal Action PlanCommunity & ChallengesProgress Review

Secara konseptual, beOkay memiliki tiga mesin utama:

Personal Metabolic Intelligence Engine — mengubah data yang memiliki provenance menjadi informasi yang dapat dipahami, dengan membedakan observasi, estimasi, dan prediksi.

Adaptive Behavior Support Engine — membantu pengguna memilih tujuan kecil yang sesuai, melaksanakan tindakan yang disetujui, lalu mengevaluasi kebiasaan secara berkala.

Community Motivation Engine — memperkuat konsistensi melalui komunitas dan tantangan yang aman, tanpa mempertandingkan kondisi medis atau mengungkap identitas kesehatan.

Tiga mesin tersebut menggunakan fondasi data dan transaksi yang sama, tetapi mempunyai batas akses dan aturan keselamatan yang berbeda.

### Keputusan arsitektur final

Aku merekomendasikan kita mempertahankan Flutter + Bun.serve + Prisma + PostgreSQL + Better Auth dari proyek sebelumnya. Tambahkan Python/LangGraph sebagai specialized intelligence service, Modal sebagai inference platform, food search adapters sebagai sumber nutrisi, dan community engine sebagai domain baru dalam core platform.

Jangan menjadikan semua kebutuhan bergantung pada LLM. Jangan melatih model sebelum problem, target label, dataset, dan evaluasinya jelas. Jangan mengorbankan privasi untuk leaderboard. Dan jangan menganggap aktivitas pengguna atau jumlah kalori sebagai bukti otomatis terjadinya perbaikan diabetes.

Identitas produk akhirnya:

beOkay — A Privacy-Preserving Hybrid Agentic Ecosystem for Preventive Metabolic Health, Personalized Nutrition, Adaptive Physical Activity, and Community-Driven Behavior Change.

Prioritas pengembangannya adalah menyelesaikan core yang sudah ada, membangun Food Intelligence yang dapat dipercaya, lalu menghubungkannya dengan wearable dan closed-loop behavioral intelligence. Setelah alur itu dapat dibuktikan end-to-end, Community & Leaderboard akan menjadi lapisan motivasi yang memperkuat manfaat produk, bukan sekadar fitur tambahan untuk terlihat menarik.

Dengan demikian, beOkay berkembang secara konsisten dari aplikasi pencatatan kesehatan menjadi ekosistem perangkat lunak yang berorientasi pada perubahan perilaku nyata, sambil tetap membatasi klaimnya pada hal yang memang dapat dibuktikan.