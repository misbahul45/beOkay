#!/usr/bin/env sh
set -eu

COMPOSE_FILE="${1:-compose.test.yaml}"
SERVICE="${2:-postgres-test}"
TARGET_DB="restore_check"

dc() { docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -c "$1"; }

COUNTS="select table_name || '=' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE' order by 1;"
EXT="select string_agg(extname, ',' order by extname) from pg_extension;"

dc 'pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/beokay-backup.dump'
dc "dropdb --if-exists -U \"\$POSTGRES_USER\" $TARGET_DB && createdb -U \"\$POSTGRES_USER\" $TARGET_DB"
dc "pg_restore --no-owner --exit-on-error -U \"\$POSTGRES_USER\" -d $TARGET_DB /tmp/beokay-backup.dump"

SRC=$(dc "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tA -c \"$COUNTS\"")
DST=$(dc "psql -U \"\$POSTGRES_USER\" -d $TARGET_DB -tA -c \"$COUNTS\"")
SRC_EXT=$(dc "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tA -c \"$EXT\"")
DST_EXT=$(dc "psql -U \"\$POSTGRES_USER\" -d $TARGET_DB -tA -c \"$EXT\"")

dc "dropdb -U \"\$POSTGRES_USER\" $TARGET_DB && rm -f /tmp/beokay-backup.dump"

TABLES=$(printf '%s\n' "$SRC" | grep -c '=')
ROWS=$(printf '%s\n' "$SRC" | awk -F= '{s+=$2} END {print s}')
if [ "$SRC" = "$DST" ] && [ "$SRC_EXT" = "$DST_EXT" ]; then
  echo "OK backup-restore: $TABLES tabel, $ROWS baris, ekstensi [$SRC_EXT] identik setelah pulih"
else
  echo "GAGAL backup-restore: isi berbeda"
  printf '%s\n' "$SRC" > /tmp/beokay-src.txt
  printf '%s\n' "$DST" | diff /tmp/beokay-src.txt - || true
  exit 1
fi
