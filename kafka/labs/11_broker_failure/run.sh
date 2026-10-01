#!/usr/bin/env bash
# Lab 11 — crash (SIGKILL) the broker that leads orders P0 while producing 200 msg/s and consuming.
source "$(dirname "$0")/../lib.sh"
RATE="${RATE:-200}"
sum_end() { kcli stats -topic orders -json | python3 -c 'import sys,json; print(json.load(sys.stdin)["total"])' ; }
end_total() { kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic orders --time -1 2>/dev/null | awk -F: '{s+=$3} END{print s}'; }
leader_of() { kcli topics -topic orders | awk -v p="$1" '$1=="orders" && $2==p {print $3}'; }

curl -s -X POST localhost:8001/stop >/dev/null
sleep 2
before="$(end_total)"
L="$(leader_of 0)"; id="${L#kafka-}"
echo "orders P0 leader = $L ; log end offsets total before = $before"
kcli brokers | grep -E "ACTIVE CONTROLLER"

banner "1. Start load: $RATE msg/s for 60s (acks=all, idempotent)"
curl -s -X POST "localhost:8001/start?mode=constant&rate=$RATE&duration=60s" >/dev/null
sleep 10
kcli topics -topic orders | tail -9

banner "2. kill -9 $L (no controlled shutdown)"
T0="$(now_ts)"; date -u +"crash at %H:%M:%S UTC"
docker compose kill -s KILL "$L" >/dev/null 2>&1
for i in 1 2 3 4 5 6; do
  sleep 3
  echo "--- +$((i*3))s"
  kcli topics -topic orders | awk '$1=="orders" || /^TOPIC/'
done
kcli brokers | grep -E "ACTIVE CONTROLLER|^[0-9]+ +(LEADER|follower)"
L2="$(leader_of 0)"
expect "orders P0 has a new leader ($L -> $L2)" test -n "$L2" -a "$L2" != "$L" -a "$L2" != "none"

banner "3. What the clients saw"
logs_since "$T0" traffic-generator | grep -iE "warn|error" | cut -c1-200 | head -5
logs_since "$T0" order-consumer-1 order-consumer-2 order-consumer-3 | grep -E "WARN|ERROR" | cut -c1-180 | head -4
echo "(full detail: Grafana > Producer Performance / Consumer Lag around $(date -u +%H:%M) UTC)"

banner "4. Restart $L: it rejoins, truncates to the high watermark, catches up, ISR expands"
T1="$(now_ts)"
docker compose start "$L" >/dev/null 2>&1
wait_healthy "$L" 180 && ok "$L healthy"
wait_isr_full 180 && ok "all replicas back in ISR"
logs_since "$T1" "$L" | grep -iE "Truncating|truncat" | head -3 | cut -c1-220

banner "5. Wait for the traffic to finish and count: every acknowledged record must be in the log"
for i in $(seq 1 40); do
  st="$(curl -s localhost:8001/status)"
  echo "$st" | grep -q '"running": false' && break
  sleep 3
done
sent="$(echo "$st" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["sent"], d["failed"])')"
after="$(end_total)"
echo "traffic: acknowledged/failed = $sent ; records appended = $((after-before))"
acked="${sent% *}"; failed="${sent#* }"
expect "no acknowledged record lost and no duplicate (appended == acked: $((after-before)) == $acked)" test "$((after-before))" = "$acked"
expect "producer saw no final failure (retries absorbed the failover)" test "$failed" = 0
sleep 10
kcli group -group order-processing-group | tail -1

banner "6. Preferred leader election moves leadership back to $L (auto.leader.rebalance, check every 30s)"
for i in $(seq 1 30); do
  [[ "$(leader_of 0)" == "$L" ]] && break
  sleep 5
done
kcli topics -topic orders | tail -9
expect "P0 led by its preferred replica $L again" test "$(leader_of 0)" = "$L"
curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null
lab_done
