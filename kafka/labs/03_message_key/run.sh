#!/usr/bin/env bash
# Lab 03 — hash(key) -> partition. Same key => same partition. No key => sticky partitioner.
source "$(dirname "$0")/../lib.sh"

banner "1. murmur2(key) % 6 (kcli computes it twice: own murmur2 + franz-go partitioner)"
kcli hash -partitions 6 order-100 order-101 order-102 user-1001 user-1002
kcli hash -partitions 12 order-100 order-101 order-102 | tail -3
echo "   ^ same keys with 12 partitions land elsewhere: adding partitions REMAPS keys."

banner "2. key=order_id: 5 events of the same order -> one partition"
parts=""
for i in 1 2 3 4 5; do
  p="$(curl -s -X POST 'localhost:8000/orders?key=order_id' -d '{"order_id":"order-lab03","user_id":1001,"product_id":500,"quantity":1}' | sed -n 's/.*"partition": \([0-9]*\).*/\1/p')"
  parts+="$p "
done
echo "order-lab03 partitions: $parts"
expect "all 5 records with key order-lab03 in the same partition" test "$(echo $parts | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')" = 1
expected="$(kcli hash -partitions 6 order-lab03 | awk 'NR==2{print $4}')"
expect "partition matches murmur2(order-lab03) % 6 = $expected" test "P$(echo $parts | awk '{print $1}')" = "$expected"

banner "3. key=user_id: different orders of the same user -> same partition (per-user ordering)"
up=""
for i in 1 2 3; do
  up+="$(curl -s -X POST 'localhost:8000/orders?key=user_id' -d '{"user_id":4242,"product_id":500,"quantity":1}' | sed -n 's/.*"partition": \([0-9]*\).*/\1/p') "
done
echo "user 4242 (3 different order ids) partitions: $up"
expect "same user -> same partition" test "$(echo $up | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')" = 1

banner "4. key=none (null key): sticky partitioner fills a batch for one partition, then switches"
np=""
for i in $(seq 1 12); do
  np+="$(curl -s -X POST 'localhost:8000/orders?key=none' -d '{"user_id":7,"product_id":7,"quantity":1}' | sed -n 's/.*"partition": \([0-9]*\).*/\1/p') "
done
echo "12 sync null-key records -> partitions: $np"
echo "   (sync sends = 1 record per batch, so the sticky partition changes almost every record)"
echo "-- 2000 null-key records, SYNC (wait for each ack -> 1 record per batch):"
kcli produce -topic ordering-demo -count 2000 -value 'nokey-{i}' -quiet | tail -1
echo "-- 2000 null-key records, ASYNC (linger 5ms -> sticky partitioner fills one partition's batch, then moves on):"
kcli produce -topic ordering-demo -count 2000 -value 'nokey-{i}' -quiet -async | tail -1
lab_done
