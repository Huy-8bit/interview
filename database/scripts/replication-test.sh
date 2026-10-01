#!/usr/bin/env bash
# =============================================================================
# End-to-end replication test:
#   1. INSERT a unique token on the PRIMARY
#   2. poll the REPLICA until the row appears
#   3. report how long it took; verify the replica rejects writes
#   ./scripts/replication-test.sh [timeout_seconds]
# =============================================================================
. "$(dirname "$0")/lib.sh"

TIMEOUT="${1:-10}"
require_running "$PRIMARY_SERVICE" "$REPLICA_SERVICE"

token="test-$(date +%s)-$RANDOM"

header "1. INSERT on primary"
psql_on "$PRIMARY_SERVICE" -c "
INSERT INTO replication_test (token, note)
VALUES ('$token', 'written by scripts/replication-test.sh')
RETURNING id, token, created_at, pg_current_wal_lsn() AS primary_lsn_after_insert;"

header "2. Poll replica (timeout ${TIMEOUT}s)"
start_ns="$(python3 -c 'import time; print(time.time_ns())' 2>/dev/null || date +%s000000000)"
deadline=$(( $(date +%s) + TIMEOUT ))
found=""
while [ "$(date +%s)" -le "$deadline" ]; do
  found="$(scalar_on "$REPLICA_SERVICE" "SELECT id FROM replication_test WHERE token = '$token'")"
  [ -n "$found" ] && break
  sleep 0.1
done
end_ns="$(python3 -c 'import time; print(time.time_ns())' 2>/dev/null || date +%s000000000)"

if [ -z "$found" ]; then
  fail "row '$token' did not reach the replica within ${TIMEOUT}s"
  exit 1
fi
ok "row id=$found visible on replica after ~$(( (end_ns - start_ns) / 1000000 )) ms (includes docker exec overhead)"
psql_on "$REPLICA_SERVICE" -c "
SELECT id, token, created_at,
       pg_last_wal_replay_lsn()        AS replica_replay_lsn,
       pg_last_xact_replay_timestamp() AS last_replayed_commit
FROM replication_test WHERE token = '$token';"

header "3. Try to write on the replica (must fail)"
if out="$(psql_on "$REPLICA_SERVICE" -c "INSERT INTO replication_test (token) VALUES ('should-fail-$token')" 2>&1)"; then
  fail "INSERT on the replica succeeded?! Is it still a standby?"
  exit 1
else
  ok "replica rejected the write:"
  echo "       $out" | grep -i error || echo "       $out"
fi

echo
ok "replication test passed"
