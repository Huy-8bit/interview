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
       CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN interval '0'
            ELSE now() - pg_last_xact_replay_timestamp() END AS replay_delay,
       r.last_msg_receipt_time
FROM pg_stat_wal_receiver r;"

receiver="$(scalar_on "$REPLICA_SERVICE" "SELECT coalesce((SELECT status FROM pg_stat_wal_receiver), 'none')")"
if [ "$receiver" = "streaming" ]; then ok "wal receiver is streaming"
else fail "wal receiver status: $receiver"; status=1; fi

header "Row counts: primary vs replica"
for t in users products orders order_items payments reviews; do
  p="$(scalar_on "$PRIMARY_SERVICE" "SELECT count(*) FROM $t")"
  r="$(scalar_on "$REPLICA_SERVICE" "SELECT count(*) FROM $t")"
  if [ "$p" = "$r" ]; then ok "$(printf '%-12s primary=%-10s replica=%s' "$t" "$p" "$r")"
  else warn "$(printf '%-12s primary=%-10s replica=%s (replica catching up?)' "$t" "$p" "$r")"; fi
done

echo
if [ "$status" -eq 0 ]; then ok "streaming replication is healthy"; else fail "replication problems detected"; fi
exit "$status"
