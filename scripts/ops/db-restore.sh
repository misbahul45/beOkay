#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Pemakaian: scripts/ops/db-restore.sh <berkas.dump> --yes [argumen docker compose ...]
  Memulihkan cadangan dari db-backup.sh ke database tujuan. Objek yang sudah ada DIHAPUS lalu dibuat ulang.
  Hentikan API lebih dulu (docker compose stop api) agar tidak ada penulisan selama pemulihan.
Env: BEOKAY_DB_SERVICE (bawaan postgres), BEOKAY_RESTORE_DB (bawaan POSTGRES_DB di container).
USAGE
}

[[ $# -ge 1 && "$1" != "-h" && "$1" != "--help" ]] || { usage; exit 0; }
file="$1"
shift
[[ "${1:-}" == "--yes" ]] || { echo "Tambahkan --yes untuk menyatakan pemulihan ini disengaja." >&2; exit 2; }
shift
[[ -f "$file" ]] || { echo "Berkas tidak ditemukan: $file" >&2; exit 1; }

if [[ -f "$file.sha256" ]]; then
  (cd "$(dirname "$file")" && sha256sum --check --quiet "$(basename "$file").sha256")
else
  echo "Peringatan: $file.sha256 tidak ada; integritas tidak diperiksa." >&2
fi

service="${BEOKAY_DB_SERVICE:-postgres}"
target="${BEOKAY_RESTORE_DB:-}"
docker compose "$@" exec -T -e TARGET_DB="$target" "$service" sh -c 'pg_restore -U "$POSTGRES_USER" -d "${TARGET_DB:-$POSTGRES_DB}" --clean --if-exists --no-owner --exit-on-error' < "$file"
echo "Dipulihkan: $file"
