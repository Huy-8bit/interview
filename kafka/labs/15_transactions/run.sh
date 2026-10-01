#!/usr/bin/env bash
# Lab 15 — exactly-once consume->process->produce with a transactional producer (txn-processor).
source "$(dirname "$0")/../lib.sh"
RUN="$(date +%s)"
T0="$(now_ts)"
kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic txn-output --time -1 > /tmp/lab15-before.txt 2>/dev/null
before="$(awk -F: '{s+=$3} END{print s}' /tmp/lab15-before.txt)"

banner "1. Three inputs; the 2nd carries lab_fault=abort_txn (first attempt aborts AFTER writing its output)"
kcli order -topic txn-input -order-id "txn-$RUN-a" -quantity 1
kcli order -topic txn-input -order-id "txn-$RUN-b" -quantity 1 -fault abort_txn
kcli order -topic txn-input -order-id "txn-$RUN-c" -quantity 1
sleep 8
logs_since "$T0" txn-processor | grep -E "TXN" | cut -c1-200
expect "an aborted transaction happened" bash -c "docker compose logs --since $T0 txn-processor | grep -q 'TXN ABORTED'"

banner "2. txn-output read with isolation.level=read_uncommitted vs read_committed"
uc="$(kcli consume -topic txn-output -from start -idle 3s -isolation uncommitted | grep -c "txn-$RUN" || true)"
cm="$(kcli consume -topic txn-output -from start -idle 3s -isolation committed | grep -c "txn-$RUN" || true)"
echo "read_uncommitted sees $uc output record(s) for this run; read_committed sees $cm"
kcli consume -topic txn-output -from start -idle 3s -isolation uncommitted | grep "txn-$RUN" | awk '{print "  uncommitted:", $1, $2, $3, $4}'
kcli consume -topic txn-output -from start -idle 3s -isolation committed | grep "txn-$RUN" | awk '{print "  committed:  ", $1, $2, $3, $4}'
expect "read_committed: exactly one output per input (3)" test "$cm" = 3
expect "read_uncommitted also sees the aborted output (>3)" test "$uc" -gt 3

banner "3. On disk: transactional batches + control records (COMMIT / ABORT markers)"
after="$(kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic txn-output --time -1 2>/dev/null | awk -F: '{s+=$3} END{print s}')"
echo "txn-output log end offsets grew by $((after-before)) for 3 committed + 1 aborted record (the extra offsets are the markers)"
p="$(kcli consume -topic txn-output -from start -idle 3s -isolation uncommitted | grep "txn-$RUN-b" | head -1 | awk '{print $2}' | tr -d P)"
leader="$(kcli topics -topic txn-output | awk -v p="$p" '$1=="txn-output" && $2==p {print $3}')"
seg="$(docker compose exec -T "$leader" sh -c "ls /var/lib/kafka/data/txn-output-$p/*.log | tail -1")"
KT_BROKER="$leader" kt kafka-dump-log --files "$seg" --print-data-log 2>/dev/null | grep -E "isTransactional: true|endTxnMarker|txn-$RUN" | sed -E 's/deleteHorizonMs.*//; s/payload: (.{60}).*/payload: \1.../' | tail -8 | cut -c1-200
n="$(KT_BROKER="$leader" kt kafka-dump-log --files "$seg" --print-data-log 2>/dev/null | grep -c 'endTxnMarker: ABORT' || true)"
expect "an ABORT control marker is on disk in txn-output P$p ($n)" test "$n" -ge 1

banner "4. Transaction coordinator state (__transaction_state)"
kt kafka-transactions --bootstrap-server "$BOOTSTRAP_INTERNAL" list 2>/dev/null
kt kafka-transactions --bootstrap-server "$BOOTSTRAP_INTERNAL" describe --transactional-id txn-processor-txn-processor-1 2>/dev/null
lab_done
