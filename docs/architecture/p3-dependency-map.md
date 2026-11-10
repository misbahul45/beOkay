# Peta ketergantungan P3 (irisan yang dibangun)

```
Flutter (Beranda: InterventionCard)
   │  GET /api/me/interventions   POST /evaluate   POST /:id/response   PATCH /intervention-preferences
   ▼
Bun API ── intervention.service ──► intervention.policy (fungsi murni, jitai-policy-v1)
   │            │                         ▲ konteks: consent, jam lokal, jatah, log keputusan sendiri, tujuan aktif
   │            ├─► intervention_decisions / intervention_preferences (PostgreSQL)
   │            └─► outbox_events ("intervention.responded") ─► pekerja dalam proses (penangan idempoten)
   └─ Tidak bergantung pada LLM, Modal, atau jaringan luar.
```
Ketergantungan keluar: hanya consent (`health_data_processing`, `personalized_ai`), preferensi zona waktu, dan tabel tujuan (`behavior_goals`, hanya membaca judul/status).

# Peta RAG gizi pada foto
```
Foto ─► Mistral (nama makanan) ─► sanitasi ─► [daftar makanan pengguna] + [referensi TKPI: kata + makna (pgvector)]
                                                   └─► gerbang kecocokan (setiap kata penting harus ada) ─► ≤ 2 padanan
UI: "{kkal} per 100 gram · nama" + "Pakai ini, lalu isi berat" (disimpan sebagai perkiraan)   |   tidak ada padanan → "Gizinya belum ketemu."
```
