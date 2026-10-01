#!/usr/bin/env bash
# =============================================================================
# Health report of the streaming replication between primary and replica.
# Exit code 0 = replica is streaming and in recovery, 1 = something is wrong.
#   ./scripts/check-replication.sh
# =============================================================================
. "$(dirname "$0")/lib.sh"

require_running "$PRIMARY_SERVICE" "$REPLICA_SERVICE"
status=0

header "PRIMARY  (localhost:${PRIMARY_PORT:-5432})"
primary_recovery="$(scalar_on "$PRIMARY_SERVICE" "SELECT pg_is_in_recovery()")"
if [ "$primary_recovery" = "f" ]; then ok "pg_is_in_recovery() = false  -> read/write primary"
else fail "pg_is_in_recovery() = $primary_recovery on the primary"; status=1; fi

echo
echo "pg_stat_replication (one row per connected standby / walsender):"
psql_on "$PRIMARY_SERVICE" -x -c "
SELECT application_name, client_addr, state, sync_state,
       pg_current_wal_lsn()                                         AS primary_current_lsn,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_lag_bytes,
       write_lag, flush_lag, replay_lag,
       backend_start
FROM pg_stat_replication;"

streaming="$(scalar_on "$PRIMARY_SERVICE" "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'")"
if [ "$streaming" -ge 1 ]; then ok "$streaming standby(s) streaming"
else fail "no standby in state 'streaming'"; status=1; fi

echo
echo "Replication slots:"
psql_on "$PRIMARY_SERVICE" -c "
SELECT slot_name, slot_type, active, active_pid, restart_lsn, wal_status,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;"

header "REPLICA  (localhost:${REPLICA_PORT:-5433})"
replica_recovery="$(scalar_on "$REPLICA_SERVICE" "SELECT pg_is_in_recovery()")"
if [ "$replica_recovery" = "t" ]; then ok "pg_is_in_recovery() = true  -> hot standby (read-only)"
else fail "pg_is_in_recovery() = $replica_recovery on the replica (was it promoted?)"; status=1; fi

echo
echo "WAL receiver + replay position:"
psql_on "$REPLICA_SERVICE" -x -c "
SELECT r.status                       AS wal_receiver_status,
       r.sender_host, r.sender_port, r.slot_name,
       pg_last_wal_receive_lsn()      AS receive_lsn,
       pg_last_wal_replay_lsn()       AS replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) AS received_not_replayed,
       pg_last_xact_replay_timestamp() AS last_replayed_commit_time,
       -- NOT a lag metric: on an idle primary this keeps growing although nothing is pending
       now() - pg_last_xact_replay_timestamp() AS since_last_replayed_commit,
       r.last_msg_receipt_time
FROM pg_stat_wal_receiver r;"

receiver="$(scalar_on "$REPLICA_SERVICE" "SELECT coalesce((SELECT status FROM pg_stat_wal_receiver), 'none')")"
if [ "$receiver" = "streaming" ]; then ok "wal receiver is streaming"
else fail "wal receiver status: $receiver"; status=1; fi

header "Replication lag  (primary current LSN vs replica replay LSN)"
# Read the replica first: the primary's LSN only moves forward, so lag >= 0.
# receive_lsn is rounded up to a WAL page boundary, so it is never compared with replay_lsn.
replica_replay_lsn="$(scalar_on "$REPLICA_SERVICE" "SELECT pg_last_wal_replay_lsn()")"
primary_lsn="$(scalar_on "$PRIMARY_SERVICE" "SELECT pg_current_wal_lsn()")"
lag_bytes="$(scalar_on "$PRIMARY_SERVICE" "SELECT pg_wal_lsn_diff('$primary_lsn', '$replica_replay_lsn')::bigint")"
lag_pretty="$(scalar_on "$PRIMARY_SERVICE" "SELECT pg_size_pretty($lag_bytes::numeric)")"
printf '  primary current LSN : %s\n  replica replay LSN  : %s\n  lag                 : %s (%s bytes)\n' \
  "$primary_lsn" "$replica_replay_lsn" "$lag_pretty" "$lag_bytes"
replay_lag_time="$(scalar_on "$PRIMARY_SERVICE" "SELECT coalesce(max(replay_lag)::text, 'n/a (idle: no WAL pending)') FROM pg_stat_replication")"
printf '  replay_lag (time)   : %s\n' "$replay_lag_time"
if [ "$lag_bytes" -le 16777216 ]; then ok "replica lag within 16 MB"
else warn "replica is $lag_pretty behind the primary"; fi

header "Table inventory and row counts: primary vs replica"
# Discover current user tables on both servers rather than maintaining a list.
# Exclude system schemas and partition children (their parent count includes them).
table_query="
SELECT format('%I.%I', n.nspname, c.relname)
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND NOT c.relispartition
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
ORDER BY 1"
primary_tables="$(scalar_on "$PRIMARY_SERVICE" "$table_query")"
replica_tables="$(scalar_on "$REPLICA_SERVICE" "$table_query")"

# Compare inventories first so added/dropped tables are reported without trying
# to count a relation that does not exist on the other server.
while IFS= read -r t; do
  [ -n "$t" ] || continue
  if ! printf '%s\n' "$replica_tables" | grep -Fqx -- "$t"; then
    fail "$t exists on primary but is missing on replica"
    status=1
    continue
  fi

  p="$(scalar_on "$PRIMARY_SERVICE" "SELECT count(*) FROM $t")"
  r="$(scalar_on "$REPLICA_SERVICE" "SELECT count(*) FROM $t")"
  if [ "$p" = "$r" ]; then
    ok "$(printf '%-36s primary=%-10s replica=%s' "$t" "$p" "$r")"
  else
    warn "$(printf '%-36s primary=%-10s replica=%s (replica may be catching up)' "$t" "$p" "$r")"
    status=1
  fi
done <<< "$primary_tables"

while IFS= read -r t; do
  [ -n "$t" ] || continue
  if ! printf '%s\n' "$primary_tables" | grep -Fqx -- "$t"; then
    fail "$t exists on replica but is missing on primary"
    status=1
  fi
done <<< "$replica_tables"

echo
if [ "$status" -eq 0 ]; then ok "streaming replication is healthy"; else fail "replication problems detected"; fi
exit "$status"
