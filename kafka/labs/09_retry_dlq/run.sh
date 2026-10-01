#!/usr/bin/env bash
# Lab 09 — retry topic + DLQ + replay.
#   A poison (quantity=-100): orders -> retry-orders x3 (2s,4s,8s backoff) -> orders-dlq
#   B malformed JSON: non-retryable -> orders-dlq immediately
#   C dependency outage: product 777 fails -> DLQ; "fix" the dependency; replay DLQ -> success
#   D replaying an unfixed poison message just sends it back to the DLQ
source "$(dirname "$0")/../lib.sh"
OC="order-consumer-1 order-consumer-2 order-consumer-3"
RUN="$(date +%s)"
kcli group -group order-processing-group -wait-members 3 -timeout 60s | head -1
# replay only what this lab creates: move the replayer group to the current end of the DLQ
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --group dlq-replayer-orders-dlq --topic orders-dlq --reset-offsets --to-latest --execute >/dev/null 2>&1 || true

banner "A. Poison message: quantity = -100"
OID="order-lab09-poison-$RUN"; T0="$(now_ts)"
kcli order -topic orders -order-id "$OID" -quantity -100
wait_log "$T0" 40 "FAILED -> orders-dlq.*key=$OID" $OC >/dev/null || true
logs_since "$T0" $OC | grep "key=$OID" | grep FAILED | sort | sed -E 's/^time=([0-9:.]+).*msg="([^"]+)".* topic=([^ ]+) partition=([0-9]+) offset=([0-9]+).*/  \1  [\3 P\4@\5]  \2/'
n="$(logs_since "$T0" $OC | grep "key=$OID" | grep -c 'FAILED -> retry-orders' || true)"
expect "3 retries through retry-orders ($n)" test "$n" = 3
expect "then dead-lettered" bash -c "docker compose logs --since $T0 $OC | grep 'key=$OID' | grep -q 'FAILED -> orders-dlq'"

banner "B. Malformed JSON (cannot be deserialized) -> non-retryable -> DLQ at once"
T1="$(now_ts)"
curl -s -X POST "localhost:8000/raw?topic=orders&key=order-lab09-garbage-$RUN&event_type=OrderCreated" -d '{"event_type":"OrderCreated", this is not json' | grep -E '"partition"|"offset"' | tr -d '\n '; echo
wait_log "$T1" 20 "FAILED -> orders-dlq.*key=order-lab09-garbage-$RUN" $OC | cut -c1-230
r="$(logs_since "$T1" $OC | grep "key=order-lab09-garbage-$RUN" | grep -c 'retry-orders' || true)"
expect "no retry for a non-retryable error ($r retries)" test "$r" = 0

banner "C. Transient dependency outage: inventory for product 777 is down"
redis_cli SADD lab:failing-products 777 >/dev/null
OID2="order-lab09-p777-$RUN"; T2="$(now_ts)"
kcli order -topic orders -order-id "$OID2" -product 777 -quantity 1
wait_log "$T2" 40 "FAILED -> orders-dlq.*key=$OID2" $OC | cut -c1-200
step "the DLQ record keeps the original coordinates + error + attempts in headers"
kcli dlq-inspect -dlq orders-dlq | grep -A5 "key=$OID2"
step "fix the dependency, then replay the DLQ (to retry-orders: only order-processing-group sees it again)"
redis_cli SREM lab:failing-products 777 >/dev/null
T3="$(now_ts)"
kcli dlq-replay -dlq orders-dlq -key "$OID2"
wait_log "$T3" 30 "processed.*key=$OID2" $OC | cut -c1-230
d="$(redis_cli HGET "lab:order:$OID2" deliveries)"
expect "replayed order processed successfully (deliveries=$d)" test "$d" = 1

banner "D. Replaying the poison message without a fix: it fails again and returns to the DLQ"
T4="$(now_ts)"
kcli dlq-replay -dlq orders-dlq -key "$OID"
wait_log "$T4" 40 "FAILED -> orders-dlq.*key=$OID" $OC | cut -c1-200
kcli dlq-inspect -dlq orders-dlq | grep -A6 "key=$OID\$" | grep -E "key=|replayed|attempts" | tail -3

banner "Metrics"
sleep 6  # one Prometheus scrape
for q in 'sum by (group) (retry_total{group=~"order-processing-group.*"})' 'sum by (group) (dlq_total{group=~"order-processing-group.*"})'; do
  echo "$q"; curl -s -G localhost:9090/api/v1/query --data-urlencode "query=$q" | python3 -c 'import sys,json; [print("   ", r["metric"].get("group"), r["value"][1]) for r in json.load(sys.stdin)["data"]["result"]]'
done
lab_done
