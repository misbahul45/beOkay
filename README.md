# beOkay

Platform pencatatan kebiasaan harian untuk orang dewasa dengan diabetes tipe 2: aplikasi Android (Flutter, `app/`), API modular (Bun + TypeScript + Prisma, `server/`), dan PostgreSQL dengan pgvector. beOkay bukan alat diagnosis dan tidak memberi saran obat.

| Kebutuhan | Tempat |
|---|---|
| Peta seluruh dokumentasi | [docs/README.md](docs/README.md) |
| Menjalankan, menguji, merilis, mencadangkan | [docs/operations/runbook.md](docs/operations/runbook.md) |
| Arsitektur sistem | [docs/architecture/system-overview.md](docs/architecture/system-overview.md) |
| Aturan kerja untuk agen | [AGENTS.md](AGENTS.md) |

Mulai cepat (semua perintah server berjalan di Docker):

```bash
cp .env.example .env
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose up --build
docker compose -f compose.test.yaml run --rm --build tester
cd app && flutter test
```
