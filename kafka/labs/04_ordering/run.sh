#!/usr/bin/env bash
# Lab 04 — Kafka orders records WITHIN a partition only.
source "$(dirname "$0")/../lib.sh"

banner "1. WITH key: 3 orders x 6 events, sent async + interleaved, read back by one consumer"
out="$(kcli ordering-test -topic ordering-demo -keys 3 -events 6)"
echo "$out"
expect "every key consumed in production order" bash -c "echo '$out' | grep -q 'Every key was consumed in production order'"

banner "2. WITHOUT key + round-robin partitioner: events of one 'order' scatter over partitions"
out2="$(kcli ordering-test -topic ordering-demo -keys 3 -events 6 -nokey -partitioner roundrobin)"
echo "$out2"
expect "events of one order land on several partitions" bash -c "echo '$out2' | grep -qE 'partitions=P[0-9],P[0-9]'"

banner "3. WITHOUT key + default sticky partitioner"
kcli ordering-test -topic ordering-demo -keys 3 -events 6 -nokey
echo "   ^ often 'in order' only because the whole burst went into ONE sticky batch — luck, not a guarantee."

banner "4. Through the real pipeline: producer API -> orders -> order-consumer (key = order id)"
T0="$(now_ts)"
redis_cli DEL lab:seq:order-lab04 >/dev/null
curl -s -X POST 'localhost:8000/orders/order-lab04/events?count=10' | grep -E '"partition"|"offset"|"sequence"' | paste - - - | head -10
wait_log "$T0" 20 "key=order-lab04.*" order-consumer-1 order-consumer-2 order-consumer-3 >/dev/null || true
sleep 2
echo "order-consumer saw (Redis list lab:seq:order-lab04, in arrival order):"
redis_cli LRANGE lab:seq:order-lab04 0 -1
seqs="$(redis_cli LRANGE lab:seq:order-lab04 0 -1 | sed -n 's/^seq=\([0-9]*\).*/\1/p' | tr '\n' ' ')"
expect "consumer received sequence 1..10 in order ($seqs)" test "$seqs" = "1 2 3 4 5 6 7 8 9 10 "
lab_done
