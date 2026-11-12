#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Pemakaian: scripts/ops/db-backup.sh [argumen docker compose ...]
  Contoh dev : scripts/ops/db-backup.sh
  Contoh prod: scripts/ops/db-backup.sh -f compose.prod.yaml --env-file .env.prod
Env: BEOKAY_BACKUP_DIR (bawaan ~/beokay-backups), BEOKAY_BACKUP_KEEP (bawaan 14), BEOKAY_DB_SERVICE (bawaan postgres).
Hasil: <dir>/beokay-<UTC>.dump (pg_dump format custom) dan .sha256. Arsip divalidasi dengan pg_restore --list sebelum disimpan.
USAGE
  exit 0
fi

dest="${BEOKAY_BACKUP_DIR:-$HOME/beokay-backups}"
keep="${BEOKAY_BACKUP_KEEP:-14}"
service="${BEOKAY_DB_SERVICE:-postgres}"
compose=(docker compose "$@")

mkdir -p "$dest"
chmod 700 "$dest"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
file="$dest/beokay-$stamp.dump"
partial="$file.partial"
trap 'rm -f "$partial"' EXIT

"${compose[@]}" exec -T "$service" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner' > "$partial"
"${compose[@]}" exec -T "$service" pg_restore --list < "$partial" > /dev/null
mv "$partial" "$file"
chmod 600 "$file"
(cd "$dest" && sha256sum "$(basename "$file")" > "$(basename "$file").sha256")

mapfile -t old < <(ls -1t "$dest"/beokay-*.dump 2>/dev/null | tail -n +"$((keep + 1))")
for f in "${old[@]}"; do rm -f "$f" "$f.sha256"; done

echo "$file"
