#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${1:-mlb}"
PSQL="${PSQL:-psql}"
CREATEDB_BIN="${CREATEDB_BIN:-createdb}"
DROPDB_BIN="${DROPDB_BIN:-dropdb}"
RECREATE_DB="${RECREATE_DB:-0}"

SQL_DIR="sql"

if [[ ! -d "$SQL_DIR" ]]; then
  echo "Expected to run from repository root containing ./sql" >&2
  exit 1
fi

if [[ "$RECREATE_DB" == "1" ]]; then
  "$DROPDB_BIN" --if-exists "$DB_NAME"
fi

if ! "$PSQL" -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1; then
  "$CREATEDB_BIN" "$DB_NAME"
fi

run_file() {
  local file="$1"
  echo "==> Applying $file"
  "$PSQL" -v ON_ERROR_STOP=1 -d "$DB_NAME" -f "$file"
}

while IFS= read -r file; do
  run_file "$file"
done < <(find "$SQL_DIR" -type f -name '*.sql' | sort)

echo "Bootstrap complete for database: $DB_NAME"