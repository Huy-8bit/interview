#!/usr/bin/env bash
# =============================================================================
# Data quality report: referential + business + temporal consistency checks,
# distributions, and sample JOIN queries (sql/verify/data-quality.sql).
#   ./scripts/verify-data.sh              # on the REPLICA (also proves replication)
#   ./scripts/verify-data.sh --primary    # on the PRIMARY
# Exit code 1 if any check FAILs.
# =============================================================================
. "$(dirname "$0")/lib.sh"

service="$REPLICA_SERVICE"
[ "${1:-}" = "--primary" ] && service="$PRIMARY_SERVICE"
require_running "$service"

header "Data quality report on $service"
started=$(date +%s)
report="$(psql_on "$service" -f /dev/stdin < sql/verify/data-quality.sql)"
echo "$report"
echo
fails="$(printf '%s\n' "$report" | grep -cE '\|\s*FAIL\s*$' || true)"
if [ "$fails" -eq 0 ]; then
  ok "all consistency checks passed ($(( $(date +%s) - started ))s)"
else
  fail "$fails consistency check(s) failed"
  exit 1
fi
