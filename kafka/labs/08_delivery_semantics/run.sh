#!/usr/bin/env bash
# Lab 08 — delivery semantics with REAL crashes (os.Exit inside the consumer).
#   A  at-least-once : process -> CRASH -> (no commit)        => redelivered => duplicate (idempotent consumer absorbs it)
#   B  at-most-once  : commit -> CRASH -> (never processed)   => message LOST
#   C  at-least-once : CRASH before processing, no commit     => processed once after restart
source "$(dirname "$0")/../lib.sh"
OC="order-consumer-1 order-consumer-2 order-consumer-3"
RUN="$(date +%s)"
recreate() { ORDER_COMMIT_MODE="$1" docker compose up -d $OC >/dev/null 2>&1; kcli group -group order-processing-group -wait-members 3 -timeout 120s | head -1; }
order_state() { echo "lab:order:$1 => $(redis_cli HGETALL "lab:order:$1" | paste -sd' ' -)"; }
wait_restart_and_stable() { sleep 3; kcli group -group order-processing-group -wait-members 3 -timeout 120s | head -1; sleep 4; }

kcli group -group order-processing-group -wait-members 3 -timeout 60s | head -1

banner "A. manual commit (process THEN commit) + crash AFTER processing, BEFORE the commit"
OID="order-lab08-dup-$RUN"; T0="$(now_ts)"
kcli order -topic orders -order-id "$OID" -quantity 3 -fault crash_after_process
wait_log "$T0" 30 "LAB FAULT.*$OID" $OC | cut -c1-220
echo "... container exits(1), docker restarts it, group rebalances, partition re-read from the LAST COMMITTED offset"
wait_log "$T0" 90 "DUPLICATE delivery detected.*key=$OID" $OC | cut -c1-220
order_state "$OID"
d="$(redis_cli HGET "lab:order:$OID" deliveries)"; q="$(redis_cli HGET "lab:order:$OID" reserved_qty)"
expect "Kafka delivered the record twice (deliveries=$d)" test "$d" = 2
expect "idempotent side effect applied once (reserved_qty=$q, quantity 3)" test "$q" = 3
docker compose ps $OC --format '{{.Service}} restarts={{.Status}}'
wait_restart_and_stable

banner "B. commit BEFORE processing (ORDER_COMMIT_MODE=before-process) + crash before processing"
recreate before-process
OID="order-lab08-loss-$RUN"; T0="$(now_ts)"
kcli order -topic orders -order-id "$OID" -quantity 2 -fault crash_before_process
wait_log "$T0" 30 "COMMIT before processing|LAB FAULT.*$OID" $OC | grep -E "LAB FAULT|COMMIT before" | tail -2 | cut -c1-200
wait_restart_and_stable
sleep 10
order_state "$OID"
d="$(redis_cli HGET "lab:order:$OID" deliveries)"
expect "record LOST: offset was committed, processing never happened (deliveries='${d}')" test -z "$d"
c="$(logs_since "$T0" $OC | grep -c "processed.*key=$OID" || true)"
expect "no consumer ever logged 'processed' for $OID ($c)" test "$c" = 0

banner "C. manual commit + crash BEFORE processing => no loss, no duplicate"
recreate manual
OID="order-lab08-safe-$RUN"; T0="$(now_ts)"
kcli order -topic orders -order-id "$OID" -quantity 1 -fault crash_before_process
wait_log "$T0" 30 "LAB FAULT.*$OID" $OC | cut -c1-200
wait_log "$T0" 90 "processed.*key=$OID" $OC | cut -c1-200
order_state "$OID"
d="$(redis_cli HGET "lab:order:$OID" deliveries)"
expect "processed exactly once after the restart (deliveries=$d)" test "$d" = 1

banner "restore default commit mode (manual)"
recreate manual
lab_done
