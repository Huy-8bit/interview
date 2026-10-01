#!/usr/bin/env bash
# =============================================================================
# Restore a pg_dump backup into the PRIMARY (the replica receives the restored
# database automatically through streaming replication).
#
#   ./scripts/restore.sh backups/ecommerce_20250101T000000Z.dump
#       -> restores into a NEW database "ecommerce_restore" (safe default)
#   ./scripts/restore.sh <file> my_copy
#       -> restores into database "my_copy" (dropped + recreated if it exists)
#   ./scripts/restore.sh <file> ecommerce --force
#       -> REPLACES the main database (terminates its connections!)
#
#   Options: --jobs N  parallel restore workers for .dump files (default 4)
# =============================================================================
. "$(dirname "$0")/lib.sh"

file=""
target="${POSTGRES_DB}_restore"
target_set=0
force=0
jobs=4
while [ $# -gt 0 ]; do
  case "$1" in
    --force)   force=1 ;;
    --jobs)    jobs="$2"; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *)
      if [ -z "$file" ]; then file="$1"
      elif [ "$target_set" -eq 0 ]; then target="$1"; target_set=1
      else fail "unexpected argument: $1"; exit 2; fi ;;
  esac
  shift
done

if [ -z "$file" ]; then
  fail "usage: $0 <backup-file> [target_db] [--force] [--jobs N]"
  echo "Available backups:"; ls -1t backups/*.dump backups/*.sql 2>/dev/null || echo "  (none) - create one with ./scripts/backup.sh"
  exit 2
fi
[ -f "$file" ] || { fail "file not found: $file"; exit 2; }
if ! [[ "$target" =~ ^[a-z_][a-z0-9_]*$ ]]; then fail "invalid database name: $target"; exit 2; fi
if [ "$target" = "$POSTGRES_DB" ] && [ "$force" -ne 1 ]; then
  fail "refusing to overwrite the main database '$POSTGRES_DB' without --force"
  exit 2
fi
if [ "$target" = "postgres" ] || [ "$target" = "template0" ] || [ "$target" = "template1" ]; then
  fail "refusing to overwrite system database '$target'"; exit 2
fi

require_running "$PRIMARY_SERVICE"
container_file="/tmp/restore_$(date +%s)_$(basename "$file")"

header "Recreate database '$target'"
docker compose exec -T "$PRIMARY_SERVICE" psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c \
  "DROP DATABASE IF EXISTS \"$target\" WITH (FORCE);" -c "CREATE DATABASE \"$target\";"

header "Restore $file -> $target"
docker compose cp "$file" "$PRIMARY_SERVICE:$container_file" >/dev/null
docker compose exec -T -u root "$PRIMARY_SERVICE" chown postgres "$container_file"
trap 'docker compose exec -T -u root "$PRIMARY_SERVICE" rm -f "$container_file" >/dev/null 2>&1 || true' EXIT

started=$(date +%s)
if [[ "$file" == *.sql ]]; then
  docker compose exec -T "$PRIMARY_SERVICE" psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$target" -f "$container_file"
else
  # --jobs: tables are loaded and indexes built by N parallel workers
  docker compose exec -T "$PRIMARY_SERVICE" pg_restore -U "$POSTGRES_USER" -d "$target" \
    --jobs="$jobs" --no-owner --exit-on-error "$container_file"
fi

# pg_restore does not restore planner statistics -> ANALYZE before using it
docker compose exec -T "$PRIMARY_SERVICE" vacuumdb -U "$POSTGRES_USER" -d "$target" --analyze-only --quiet
ok "restore finished in $(( $(date +%s) - started ))s"

header "Verify"
docker compose exec -T "$PRIMARY_SERVICE" psql -X -U "$POSTGRES_USER" -d "$target" -c "
SELECT relname AS table_name, n_live_tup AS rows
FROM pg_stat_user_tables ORDER BY n_live_tup DESC;" -c "
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;"
echo "Connect: psql -h localhost -p ${PRIMARY_PORT:-5432} -U $POSTGRES_USER -d $target"
