#!/usr/bin/env bash
# Interactive psql inside a container (no local PostgreSQL client needed).
#   ./scripts/psql.sh                 # primary
#   ./scripts/psql.sh replica         # replica
#   ./scripts/psql.sh primary -c "SELECT count(*) FROM orders"
#   ./scripts/psql.sh primary -f /dev/stdin < sql/monitoring/locks.sql
. "$(dirname "$0")/lib.sh"

target="${1:-primary}"
[ $# -gt 0 ] && shift
case "$target" in
  primary) service="$PRIMARY_SERVICE" ;;
  replica) service="$REPLICA_SERVICE" ;;
  *) fail "usage: $0 [primary|replica] [psql args...]"; exit 2 ;;
esac

if [ -t 0 ]; then tty_flag=(); else tty_flag=(-T); fi
exec docker compose exec "${tty_flag[@]}" "$service" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"
