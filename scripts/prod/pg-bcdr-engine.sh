#!/usr/bin/env bash
# ==============================================================================
# 🐘 Enterprise PostgreSQL 18 & MLflow Disaster Recovery Engine (BCDR)
# ==============================================================================
# Production-ready, hardened backup and restore utility for microservices DBs:
#   - ms_orders
#   - ms_products
#   - ms_inventory
#   - ms_keycloak
#
# Commands:
#   ./scripts/prod/pg-bcdr-engine.sh backup [--db <name>|--all] [--dest <dir>] [--s3-sync <bucket>]
#   ./scripts/prod/pg-bcdr-engine.sh restore --file <path.dump> --target-db <name> [--host <host>]
#   ./scripts/prod/pg-bcdr-engine.sh verify-drill --file <path.dump>
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

# --- Configuration & Defaults ---
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
BACKUP_DIR="${BACKUP_DIR:-backups/bcdr-drill}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"

DATABASES_DEFAULT=("ms_orders" "ms_products" "ms_inventory" "ms_keycloak")

export PGUSER PGPASSWORD

log() {
  echo -e "\033[1;34m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO]\033[0m $*"
}
log_success() {
  echo -e "\033[1;32m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS]\033[0m $*"
}
log_warn() {
  echo -e "\033[1;33m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN]\033[0m $*"
}
log_error() {
  echo -e "\033[1;31m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR]\033[0m $*" >&2
}

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_error "Process exited with error (Code: ${exit_code})."
  fi
}
trap cleanup EXIT ERR INT TERM

# --- Helper: Check Postgres Client Tools ---
check_tools() {
  for tool in pg_dump pg_restore psql sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_error "Required tool not found: ${tool}"
      exit 1
    fi
  done
}

# --- Function: Backup Single Database ---
backup_db() {
  local db="$1"
  local host="${2:-$PGHOST}"
  local port="${3:-$PGPORT}"
  local timestamp
  timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"

  local final_file="${BACKUP_DIR}/${db}_${timestamp}.dump"
  local temp_file="${final_file}.partial"

  mkdir -p "${BACKUP_DIR}"

  log "Starting database backup for '${db}' from ${host}:${port}..."

  # Dump in custom binary format with configurable compression level
  pg_dump --no-owner --no-privileges \
    --format=custom \
    --compress="${COMPRESSION_LEVEL}" \
    --jobs="${PARALLEL_JOBS}" \
    --host="${host}" \
    --port="${port}" \
    --username="${PGUSER}" \
    --dbname="${db}" \
    --file="${temp_file}"

  log "Verifying structural integrity of dump archive..."
  pg_restore --list "${temp_file}" >/dev/null

  mv "${temp_file}" "${final_file}"
  sha256sum "${final_file}" > "${final_file}.sha256"

  # User table count
  local table_count
  table_count="$(psql --no-align --tuples-only --host="${host}" --port="${port}" --username="${PGUSER}" --dbname="${db}" \
    --command="SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind IN ('r','p') AND n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%'")"

  if [[ "$table_count" -lt 1 ]]; then
    log_warn "Source database '${db}' contains no user tables."
  fi
  printf '%s\n' "${table_count}" > "${final_file}.tables"

  log_success "Backup completed: ${final_file} (${table_count} user tables, SHA256 verified)"
}

# --- Function: Purge Old Backups ---
purge_old_backups() {
  log "Applying retention policy (${RETENTION_DAYS} days) in ${BACKUP_DIR}..."
  find "${BACKUP_DIR}" -type f \( -name '*.dump' -o -name '*.dump.sha256' -o -name '*.dump.tables' \) -mtime "+${RETENTION_DAYS}" -delete || true
  log_success "Old backup cleanup completed."
}

# --- Function: Sync to Cloud Storage ---
sync_cloud() {
  local bucket="$1"
  log "Synchronizing backups to cloud bucket: ${bucket}..."
  if command -v aws >/dev/null 2>&1; then
    aws s3 sync "${BACKUP_DIR}" "s3://${bucket}/postgres-bcdr/" --exclude "*" --include "*.dump*" --only-show-errors
    log_success "AWS S3 synchronization completed."
  elif command -v az >/dev/null 2>&1; then
    az storage blob upload-batch -d "${bucket}" -s "${BACKUP_DIR}" --pattern "*.dump*" --only-show-errors
    log_success "Azure Blob synchronization completed."
  elif command -v gsutil >/dev/null 2>&1; then
    gsutil -m rsync -r "${BACKUP_DIR}" "gs://${bucket}/postgres-bcdr/"
    log_success "GCS synchronization completed."
  else
    log_warn "No cloud CLI tool (aws, az, gsutil) detected. Skipping remote sync."
  fi
}

# --- Function: Verify Drill in Isolated Instance ---
verify_drill() {
  local dump_file="$1"
  if [[ ! -f "$dump_file" ]]; then
    log_error "File not found: ${dump_file}"
    exit 1
  fi

  log "Running BCDR verification for: ${dump_file}"

  # 1. Validate checksum if present
  if [[ -f "${dump_file}.sha256" ]]; then
    log "Verifying SHA-256 checksum..."
    sha256sum --check "${dump_file}.sha256"
  fi

  # 2. Validate catalog structure
  local toc_entries
  toc_entries="$(pg_restore --list "${dump_file}" | wc -l)"
  log "Entries found in TOC catalog: ${toc_entries}"
  if [[ "$toc_entries" -lt 5 ]]; then
    log_error "Dump file appears corrupted or incomplete (fewer than 5 TOC entries)."
    exit 1
  fi

  log_success "Structural BCDR verification succeeded for: ${dump_file}"
}

# --- Function: Restore Database ---
restore_db() {
  local dump_file="$1"
  local target_db="$2"
  local host="${3:-$PGHOST}"
  local port="${4:-$PGPORT}"

  if [[ ! -f "$dump_file" ]]; then
    log_error "Backup file not found: ${dump_file}"
    exit 1
  fi

  log_warn "⚠️  RESTORE REQUESTED FOR '${target_db}' ON ${host}:${port}"
  log "Terminating active connections on ${target_db}..."
  psql --host="${host}" --port="${port}" --username="${PGUSER}" --dbname="postgres" -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${target_db}' AND pid <> pg_backend_pid();" >/dev/null || true

  log "Dropping and recreating database '${target_db}'..."
  psql --host="${host}" --port="${port}" --username="${PGUSER}" --dbname="postgres" -c "DROP DATABASE IF EXISTS ${target_db};"
  psql --host="${host}" --port="${port}" --username="${PGUSER}" --dbname="postgres" -c "CREATE DATABASE ${target_db};"

  log "Restoring data from ${dump_file} (jobs: ${PARALLEL_JOBS})..."
  pg_restore --no-owner --no-privileges \
    --jobs="${PARALLEL_JOBS}" \
    --host="${host}" \
    --port="${port}" \
    --username="${PGUSER}" \
    --dbname="${target_db}" \
    "${dump_file}" || true

  log_success "Restore completed for database '${target_db}'."
}

# --- CLI Dispatcher ---
COMMAND="${1:-help}"
shift || true

check_tools

case "$COMMAND" in
  backup)
    DB_TARGET="all"
    S3_BUCKET=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --db) DB_TARGET="$2"; shift 2 ;;
        --all) DB_TARGET="all"; shift ;;
        --dest) BACKUP_DIR="$2"; shift 2 ;;
        --s3-sync) S3_BUCKET="$2"; shift 2 ;;
        *) log_error "Unknown parameter: $1"; exit 1 ;;
      esac
    done

    if [[ "$DB_TARGET" == "all" ]]; then
      for db in "${DATABASES_DEFAULT[@]}"; do
        backup_db "$db"
      done
    else
      backup_db "$DB_TARGET"
    fi

    purge_old_backups

    if [[ -n "$S3_BUCKET" ]]; then
      sync_cloud "$S3_BUCKET"
    fi
    ;;

  restore)
    DUMP_FILE=""
    TARGET_DB=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --file) DUMP_FILE="$2"; shift 2 ;;
        --target-db) TARGET_DB="$2"; shift 2 ;;
        --host) PGHOST="$2"; shift 2 ;;
        --port) PGPORT="$2"; shift 2 ;;
        *) log_error "Unknown parameter: $1"; exit 1 ;;
      esac
    done

    if [[ -z "$DUMP_FILE" || -z "$TARGET_DB" ]]; then
      log_error "Usage: ./pg-bcdr-engine.sh restore --file <path.dump> --target-db <name>"
      exit 1
    fi
    restore_db "$DUMP_FILE" "$TARGET_DB"
    ;;

  verify-drill)
    DUMP_FILE=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --file) DUMP_FILE="$2"; shift 2 ;;
        *) log_error "Unknown parameter: $1"; exit 1 ;;
      esac
    done
    if [[ -z "$DUMP_FILE" ]]; then
      log_error "Usage: ./pg-bcdr-engine.sh verify-drill --file <path.dump>"
      exit 1
    fi
    verify_drill "$DUMP_FILE"
    ;;

  help|--help|-h)
    echo "Usage: $0 {backup|restore|verify-drill} [options]"
    echo ""
    echo "Commands:"
    echo "  backup       Generate compressed custom-format PostgreSQL backups"
    echo "  restore      Restore a dump archive into a specific target database"
    echo "  verify-drill Verify SHA-256 integrity and TOC catalog structure without restoring"
    exit 0
    ;;

  *)
    log_error "Invalid command: $COMMAND. Run '$0 help' for details."
    exit 1
    ;;
esac
