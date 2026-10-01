#!/usr/bin/env bash
# =============================================================================
# Logical backup with pg_dump (custom format: compressed, restorable in
# parallel and selectively with pg_restore).
#
#   ./scripts/backup.sh                    # dump ecommerce from the PRIMARY
#   ./scripts/backup.sh --from-replica     # dump from the REPLICA (offload the primary)
#   ./scripts/backup.sh --plain            # plain SQL (.sql) instead of custom format
#   ./scripts/backup.sh --db other_db
#
# Output: ./backups/<db>_<UTC timestamp>.dump  (or .sql)
# =============================================================================
. "$(dirname "$0")/lib.sh"

source_service="$PRIMARY_SERVICE"
format="custom"
db="$POSTGRES_DB"
while [ $# -gt 0 ]; do
  case "$1" in
    --from-replica) source_service="$REPLICA_SERVICE" ;;
    --plain)        format="plain" ;;
    --db)           db="$2"; shift ;;
    -h|--help)      sed -n '2,13p' "$0"; exit 0 ;;
    *)              fail "unknown argument: $1"; exit 2 ;;
  esac
  shift
done

require_running "$source_service"
mkdir -p backups
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [ "$format" = "custom" ]; then
  file="backups/${db}_${stamp}.dump"
  fmt_args=(--format=custom --compress=6)
else
  file="backups/${db}_${stamp}.sql"
  fmt_args=(--format=plain --no-owner --no-privileges)
fi

header "pg_dump $db from $source_service -> $file"
started=$(date +%s)
# pg_dump runs inside the container and streams to stdout -> file on the host.
# It takes an MVCC snapshot: a consistent backup while the database stays online.
if ! docker compose exec -T "$source_service" \
     pg_dump -U "$POSTGRES_USER" -d "$db" "${fmt_args[@]}" > "$file"; then
  rm -f "$file"
  fail "pg_dump failed"
  exit 1
fi
elapsed=$(( $(date +%s) - started ))

ok "backup written: $file ($(du -h "$file" | cut -f1), ${elapsed}s)"
if [ "$format" = "custom" ]; then
  echo
  echo "Table of contents (first entries) - inspect with: pg_restore --list $file"
  docker compose exec -T "$source_service" pg_restore --list < "$file" | grep -E ' TABLE (DATA )?public ' | head -12 || true
  echo
  echo "Restore into a new database:  ./scripts/restore.sh $file"
fi
