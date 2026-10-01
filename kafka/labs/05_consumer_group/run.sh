#!/usr/bin/env bash
# Lab 05 — consumer group = unit of parallelism. 3 consumers / 6 partitions, then 8 consumers, then many groups.
source "$(dirname "$0")/../lib.sh"

banner "1. order-processing-group: 3 instances share 6 partitions (assignment chosen by the group leader)"
kcli group -group order-processing-group -wait-members 3 -timeout 60s
for p in 8011 8012 8013; do curl -s localhost:$p/admin/state | grep -A3 '"assignment"' | tr -d '\n ' ; echo; done

banner "2. Scale to 8 instances (docker compose --profile scale up -d) — only 6 can work"
T0="$(now_ts)"
docker compose --profile scale up -d order-consumer-4 order-consumer-5 order-consumer-6 order-consumer-7 order-consumer-8 2>&1 | grep -c Started | sed 's/^/started containers: /'
out="$(kcli group -group order-processing-group -wait-members 8 -timeout 120s)"
echo "$out"
idle="$(echo "$out" | grep -c 'IDLE member' || true)"
expect "8 members, exactly 2 idle (6 partitions)" test "$idle" = 2
echo
echo "rebalance log lines since scale-up:"
order_consumer_logs "$T0" | grep REBALANCE | cut -c1-200 | head -12
logs_since "$T0" order-consumer-4 order-consumer-5 order-consumer-6 order-consumer-7 order-consumer-8 | grep REBALANCE | cut -c1-200 | head -12

banner "3. Scale back to 3"
docker compose --profile scale stop order-consumer-4 order-consumer-5 order-consumer-6 order-consumer-7 order-consumer-8 >/dev/null 2>&1
docker compose --profile scale rm -f order-consumer-4 order-consumer-5 order-consumer-6 order-consumer-7 order-consumer-8 >/dev/null 2>&1
kcli group -group order-processing-group -wait-members 3 -timeout 60s | head -6

banner "4. Different groups = independent copies of the stream (each has its own committed offsets)"
T1="$(now_ts)"
resp="$(curl -s -X POST localhost:8000/orders -d '{"user_id":1001,"product_id":500,"quantity":1}')"
key="$(echo "$resp" | sed -n 's/.*"key": "\(.*\)".*/\1/p')"
echo "produced $key once"
for svc in order-consumer-1 order-consumer-2 order-consumer-3 payment-consumer notification-consumer; do
  wait_log "$T1" 20 "processed.*topic=orders.*key=$key" "$svc" 2>/dev/null | sed -E 's/.*consumer=([^ ]+) group=([^ ]+).*partition=([0-9]+) offset=([0-9]+).*/  consumer=\1 group=\2 partition=\3 offset=\4/' || true
done
n="$(logs_since "$T1" order-consumer-1 order-consumer-2 order-consumer-3 payment-consumer notification-consumer | grep -c "processed.*topic=orders.*key=$key" || true)"
expect "the record was processed once per group (3 groups => 3 lines, got $n)" test "$n" = 3
kcli groups
lab_done
