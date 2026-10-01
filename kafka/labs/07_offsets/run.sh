#!/usr/bin/env bash
# Lab 07 — log start / log end (HW) / committed offset / lag, replay with reset-offsets,
# auto-commit sawtooth, and where commits physically live (__consumer_offsets).
source "$(dirname "$0")/../lib.sh"
G=lab-07-replay
java_hash_partition() { python3 - "$1" "$2" <<'PY'
import sys
h = 0
for ch in sys.argv[1]:
    h = (31 * h + ord(ch)) & 0xFFFFFFFF
if h >= 2**31: h -= 2**32
print((0 if h == -2**31 else abs(h)) % int(sys.argv[2]))  # Utils.abs(groupId.hashCode()) % partitions
PY
}

banner "1. Partition offsets of orders: log start (earliest) and log end / high watermark (latest)"
echo "earliest (--time -2):"; kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic orders --time -2
echo "latest   (--time -1):"; kt kafka-get-offsets --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic orders --time -1

banner "2. Committed offsets + lag of order-processing-group (kafka-consumer-groups.sh)"
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --group order-processing-group 2>/dev/null | cut -c1-150

banner "3. Lag grows while consumers are down, drains when they come back"
curl -s -X POST "localhost:8001/start?mode=constant&rate=50&duration=0s" >/dev/null
docker compose stop order-consumer-1 order-consumer-2 order-consumer-3 >/dev/null 2>&1
echo "consumers stopped; traffic 50 msg/s for 10s ..."; sleep 10
lag_down="$(kcli group -group order-processing-group | sed -n 's/.*total lag: \([0-9]*\).*/\1/p')"
kcli group -group order-processing-group | tail -8
docker compose start order-consumer-1 order-consumer-2 order-consumer-3 >/dev/null 2>&1
kcli group -group order-processing-group -wait-members 3 -timeout 90s >/dev/null
sleep 5
lag_up="$(kcli group -group order-processing-group | sed -n 's/.*total lag: \([0-9]*\).*/\1/p')"
echo "lag while down: $lag_down   lag 5s after restart: $lag_up"
expect "lag accumulated while consumers were stopped (>= 300)" test "${lag_down:-0}" -ge 300
expect "lag drained after restart (< 100)" test "${lag_up:-999999}" -lt 100

banner "4. Auto-commit sawtooth: analytics-group commits every 5s (COMMIT_MODE=auto)"
for i in $(seq 1 12); do
  printf "t=%2ss analytics-group lag=%s   order-processing-group lag=%s\n" "$i" \
    "$(kcli group -group analytics-group | sed -n 's/.*total lag: \([0-9]*\).*/\1/p')" \
    "$(kcli group -group order-processing-group | sed -n 's/.*total lag: \([0-9]*\).*/\1/p')"
  sleep 1
done
echo "   ^ lag is computed from COMMITTED offsets: it jumps down only when a commit lands."
curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null

banner "5. Replay: a NEW group positioned with kafka-consumer-groups --reset-offsets (group must be inactive)"
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --delete --group "$G" >/dev/null 2>&1 || true
step "--to-earliest (dry run is the default; --execute writes the commit)"
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --group "$G" --topic orders --reset-offsets --to-earliest --execute 2>/dev/null
step "--shift-by -5 on partition 0 only"
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --group "$G" --topic orders:0 --reset-offsets --to-latest --execute >/dev/null 2>&1
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --group "$G" --topic orders:0 --reset-offsets --shift-by -5 --execute 2>/dev/null
step "--to-datetime (replay everything produced in the last 2 minutes)"
since="$(python3 -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=2)).strftime("%Y-%m-%dT%H:%M:%S.000"))')"
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --group "$G" --topic orders --reset-offsets --to-datetime "$since" --execute 2>/dev/null
step "describe $G (no members: committed offsets exist without any consumer)"
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --group "$G" 2>/dev/null | cut -c1-120
step "consume 5 records as $G -> starts exactly at the committed offsets"
kcli consume -group "$G" -topic orders -max 5 -max-value 60 -idle 10s

banner "6. Where is a commit stored? __consumer_offsets partition = Utils.abs(group.id.hashCode()) % 50"
p="$(java_hash_partition "$G" 50)"
echo "group $G -> __consumer_offsets partition $p (its leader is the GROUP COORDINATOR of $G)"
kcli topics -topic __consumer_offsets -internal | awk -v p="$p" 'NR<=3 || $2==p'
kt kafka-console-consumer --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic __consumer_offsets --partition "$p" --offset earliest \
  --formatter org.apache.kafka.tools.consumer.OffsetsMessageFormatter --timeout-ms 5000 2>/dev/null | grep "$G" | tail -4 | cut -c1-220
n="$(kt kafka-console-consumer --bootstrap-server "$BOOTSTRAP_INTERNAL" --topic __consumer_offsets --partition "$p" --offset earliest \
  --formatter org.apache.kafka.tools.consumer.OffsetsMessageFormatter --timeout-ms 5000 2>/dev/null | grep -c "$G" || true)"
expect "commit records of $G found in __consumer_offsets partition $p ($n)" test "$n" -gt 0
step "records per __consumer_offsets partition: groups that commit often make 'their' partition hot"
kcli stats -topic __consumer_offsets | grep -vE " 0  " | tail -12
kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --delete --group "$G" >/dev/null 2>&1 || true
lab_done
