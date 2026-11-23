#!/usr/bin/env bash
# Run an isolated, synthetic PostgreSQL backup and restore verification.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="${SCRIPT_DIR}/pg-bcdr-engine.sh"
DRILL_ID="$(date -u +%Y%m%d%H%M%S)_${RANDOM}"
SOURCE_DB="bcdr_source_${DRILL_ID}"
TARGET_DB="bcdr_restore_${DRILL_ID}"
DRILL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bcdr-restore-drill.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  dropdb --if-exists --host="${PGHOST:-localhost}" --port="${PGPORT:-5432}" --username="${PGUSER:-postgres}" "${TARGET_DB}" >/dev/null 2>&1 || true
  dropdb --if-exists --host="${PGHOST:-localhost}" --port="${PGPORT:-5432}" --username="${PGUSER:-postgres}" "${SOURCE_DB}" >/dev/null 2>&1 || true
  rm -rf -- "${DRILL_DIR}"
  exit "$status"
}
trap cleanup EXIT

for tool in createdb dropdb psql; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Required tool not found: $tool" >&2; exit 1; }
done

createdb --host="${PGHOST:-localhost}" --port="${PGPORT:-5432}" --username="${PGUSER:-postgres}" "${SOURCE_DB}"
psql --no-align --tuples-only --set=ON_ERROR_STOP=1 --host="${PGHOST:-localhost}" --port="${PGPORT:-5432}" --username="${PGUSER:-postgres}" --dbname="${SOURCE_DB}" <<'SQL'
CREATE TABLE bcdr_probe (id integer PRIMARY KEY, payload text NOT NULL);
INSERT INTO bcdr_probe (id, payload) VALUES (1, 'restore-drill-ok'), (2, 'checksum-verified');
SQL

export BACKUP_DIR="${DRILL_DIR}"
bash "$ENGINE" backup --db "$SOURCE_DB" --dest "$DRILL_DIR"
DUMP_FILE="$(find "$DRILL_DIR" -maxdepth 1 -type f -name "${SOURCE_DB}_*.dump" -print -quit)"
[[ -n "$DUMP_FILE" && -s "$DUMP_FILE" ]] || { echo "Backup archive was not created." >&2; exit 1; }
bash "$ENGINE" verify-drill --file "$DUMP_FILE"

started_at="$(date +%s)"
bash "$ENGINE" restore --file "$DUMP_FILE" --target-db "$TARGET_DB" --execute
elapsed_seconds=$(( $(date +%s) - started_at ))
restored_rows="$(psql --no-align --tuples-only --set=ON_ERROR_STOP=1 --host="${PGHOST:-localhost}" --port="${PGPORT:-5432}" --username="${PGUSER:-postgres}" --dbname="${TARGET_DB}" --command="SELECT string_agg(id || ':' || payload, ',' ORDER BY id) FROM bcdr_probe")"
[[ "$restored_rows" == "1:restore-drill-ok,2:checksum-verified" ]] || {
  echo "Restored data mismatch: ${restored_rows}" >&2
  exit 1
}

echo "BCDR restore drill passed; restored 2 synthetic rows in ${elapsed_seconds}s."
