#!/usr/bin/env bash
# Lab 01 — follow ONE message: HTTP -> producer -> broker (partition/offset) -> consumers of 3 groups.
source "$(dirname "$0")/../lib.sh"
T0="$(now_ts)"

banner "1. POST /orders (sync: the HTTP call waits for the broker ack, acks=all)"
resp="$(curl -s -X POST localhost:8000/orders -H 'content-type: application/json' -d '{"user_id":1001,"product_id":500,"quantity":2}')"
echo "$resp"
key="$(echo "$resp" | sed -n 's/.*"key": "\(.*\)".*/\1/p')"
part="$(echo "$resp" | sed -n 's/.*"partition": \([0-9]*\).*/\1/p')"
off="$(echo "$resp" | sed -n 's/.*"offset": \([0-9]*\).*/\1/p')"
expect "producer returned topic/partition/offset" test -n "$part" -a -n "$off"

banner "2. Producer log line"
sleep 1
logs_since "$T0" producer-service | grep "$key" || true

banner "3. The record as stored in partition $part at offset $off (kcli consume, no consumer group)"
kcli consume -topic orders -partition "$part" -from "$off" -max 1 -headers

banner "4. Who consumed it? (order-processing-group, payment-group, notification-group, analytics-group)"
line="$(wait_log "$T0" 30 "key=$key .*|processed.*key=$key" order-consumer-1 order-consumer-2 order-consumer-3 | grep processed | head -1 || true)"
echo "$line"
expect "order-consumer processed the same partition/offset" bash -c "echo '$line' | grep -q 'partition=$part offset=$off'"
pay="$(wait_log "$T0" 30 "processed.*topic=orders.*key=$key" payment-consumer || true)"
echo "$pay"
expect "payment-consumer processed it too (separate group, same record)" test -n "$pay"
notif="$(wait_log "$T0" 30 "processed.*topic=orders.*key=$key" notification-consumer || true)"
echo "$notif"
expect "notification-consumer processed it too" test -n "$notif"

banner "5. Follow-up event: payment-consumer produced PaymentSucceeded on topic payments (same key = order id)"
pe="$(wait_log "$T0" 30 "processed.*topic=payments.*key=$key" notification-consumer || true)"
echo "$pe"
expect "notification-consumer consumed the payment event of this order" test -n "$pe"

banner "6. Async produce: HTTP returns 202 BEFORE the broker ack"
curl -s -X POST 'localhost:8000/orders?mode=async' -d '{"user_id":1002,"product_id":501,"quantity":1}' | head -12
sleep 1
wait_log "$T0" 10 "async ack" producer-service | tail -1
lab_done
