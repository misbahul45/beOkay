# Core Health Experience — audit awal

Pembaruan Slice 2: Nutrition online, integrasi Today, meal-only timeline/daily read dan Quick Record food sudah dikerjakan; lihat [laporan Nutrition](../reports/nutrition-implementation.md). Klasifikasi tabel di bawah adalah audit sebelum implementasi. Offline, weekly analytics dan domain lain tetap belum selesai.

Tanggal: 8 November 2026. Cakupan eksekusi: audit dan Slice 1 Today Foundation; berhenti untuk review pengguna sebelum Slice 2. Working tree bersih saat mulai.

Status di bawah berasal dari inspeksi sumber; hasil runtime dicatat terpisah di laporan implementasi. Dokumen audit auth lama mengandung catatan historis yang tidak menggambarkan seluruh keadaan sekarang.

| Area / fitur | Klasifikasi awal | Bukti / gap | Prioritas dan solusi | Verifikasi |
|---|---|---|---|---|
| Auth, verifikasi, reset, bearer | EXISTS_BUT_INCOMPLETE | `server/src/features/auth`, `app/lib/features/auth`; integrasi identity tersedia; reset dan isolasi dua akun belum tercakup | P0: pertahankan Better Auth | regresi identity dan guard Today |
| Consent / onboarding | EXISTS_BUT_INCOMPLETE | service consent memeriksa versi kebijakan; onboarding server dan router tersedia; teks kebijakan draf | P0: gunakan guard yang sama | grant/withdraw dan 403 Today |
| Profil / kesehatan / preferensi | EXISTS_BUT_INCOMPLETE | modul API dan Flutter tersedia; IANA timezone dan unit tersimpan | P0: reuse; jangan duplikasi identitas | DB terisolasi, preferensi Today |
| Today | EXISTS_BUT_INCOMPLETE | `home_screen.dart` hanya profil dan pemberitahuan pencatatan belum tersedia; belum ada read model | P0 Slice 1: endpoint dan dashboard foundation | unit, integrasi, widget |
| Quick Record | MISSING | belum ada form domain | P0 Slice 2 dst.; jangan tombol simpan palsu | journey tiap domain |
| Nutrition / Glucose / Activity | MISSING | tidak ada modul tracking, tabel, form atau histori domain | P0 Slice 2–4 | migrasi, domain, API, widget, Bruno |
| Medication / Goals | MISSING | tidak ada regimen, jadwal, intake atau check-in | P0 Slice 5–6 | keadaan dan ownership |
| Timeline | MISSING | tidak ada query lintas domain | P0 Slice 7: read model dari tabel sumber | urutan occurrence, pagination |
| Insights / summaries | MISSING | tidak ada derived metrics atau invalidasi | P0 Slice 8: aturan coverage dan freshness | koreksi dan hitung ulang |
| Offline / sync / revisions | MISSING | secure token storage tersedia, bukan penyimpanan health/offline | P0 Slice 9: account-scoped durable queue | restart, retry, conflict, logout |
| Privacy integration tracking | MISSING | guard consent tersedia; belum ada tracking untuk dilindungi | P0: consent pada setiap endpoint | isolasi dan withdrawal |
| Tema / router / komponen | EXISTS_BUT_INCOMPLETE | Riverpod, go_router, Inter, tokens, PageScaffold, InfoCard, PillNavBar; dua tab saat ini | reuse tema, hindari navigasi mati | ukuran kecil, teks besar, error |
| FigCraft | EXISTS_BUT_INCOMPLETE | `design/beOkay-ui.figcraft` arsip tersedia; MCP FigCraft tidak tersedia pada sesi | spec reviewable sesuai fallback prompt | belum bisa membuktikan editable handoff / parity |
| Bruno | MISSING | tidak ditemukan koleksi existing di repository | satu koleksi awal, environment bersama tanpa kredensial | CLI bila tersedia |
| Tests / Docker | EXISTS_BUT_INCOMPLETE | Flutter flow/unit tests, satu integrasi identity; DB test terpisah tmpfs | jalankan regresi dalam Docker untuk backend | hasil aktual di laporan |
| Jobs / cache | NOT_APPLICABLE | belum diperlukan untuk Today foundation tanpa tracking | hindari cache health; no-store | header dan fresh request |
| P1 | MISSING | reminder, media, devices, export belum ada | sesudah P0; belum diimplementasikan | acceptance terpisah |

Risiko: jangan mengartikan modul belum diimplementasikan sebagai histori kosong yang sudah diverifikasi; gunakan availability eksplisit dan nilai null. Jangan memakai jam host/server untuk tanggal pengguna. Provider Today harus dibuang saat identitas, consent atau preferensi berubah. Jangan memuat seluruh histori untuk Today saat domain ditambahkan nanti.

Urutan rencana: Today Foundation → review → Nutrition → review → Glucose → review → Activity → review → Medication → review → Goals → review → Timeline → review → Insights → review → Offline & Integrity → review → P1 bersyarat. Tiap slice membawa skema/kontrak/desain/implementasi/tes/Bruno yang terkait, bukan seluruh tabel sekaligus.
