#!/usr/bin/env bash
# Lab 12 — hot key -> hot partition -> one consumer saturated while the others idle.
source "$(dirname "$0")/../lib.sh"
RATE="${RATE:-600}"
cleanup() {
  for p in 8011 8012 8013; do curl -s -X POST "localhost:$p/admin/delay?ms=0" >/dev/null; curl -s -X POST "localhost:$p/admin/log-every?n=1" >/dev/null; done
  curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null
}
trap cleanup EXIT

banner "0. Where does the hot key go?"
kcli hash -partitions 6 order-HOT
HOT="$(kcli hash -partitions 6 order-HOT | awk 'NR==2{print $4}')"
kcli group -group order-processing-group -wait-members 3 -timeout 60s | grep -E "MEMBER|order-consumer"

banner "1. Uniform keys for 20s at $RATE msg/s (baseline)"
for p in 8011 8012 8013; do curl -s -X POST "localhost:$p/admin/log-every?n=500" >/dev/null; done
kcli stats -topic orders -snapshot /tmp/lab12-a.json
curl -s -X POST "localhost:8001/start?mode=constant&rate=$RATE&duration=20s" >/dev/null; sleep 22
kcli stats -topic orders -since /tmp/lab12-a.json

banner "2. Skewed keys for 30s: 80% of records use key order-HOT"
kcli stats -topic orders -snapshot /tmp/lab12-b.json
for p in 8011 8012 8013; do curl -s -X POST "localhost:$p/admin/delay?ms=2" >/dev/null; done
echo "each consumer now needs ~2ms/record => ~500 records/s per partition max (partitions are processed sequentially)"
curl -s -X POST "localhost:8001/start?mode=skewed-key&rate=$RATE&duration=30s&hot_ratio=0.8" >/dev/null
sleep 20
step "lag per partition after 20s of skew"
kcli group -group order-processing-group | sed -n '/TOPIC/,$p'
sleep 12
out="$(kcli stats -topic orders -since /tmp/lab12-b.json)"; echo "$out"
expect "hot partition $HOT detected (max/avg >= 3)" bash -c "echo '$out' | grep -q 'HOT PARTITION'"
step "processing rate per partition (Prometheus, last 30s)"
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=sum by (partition, instance) (rate(consumed_total{group="order-processing-group",topic="orders"}[30s]))' \
 | python3 -c 'import sys,json; [print("   P%-2s %-18s %7.1f rec/s" % (r["metric"]["partition"], r["metric"]["instance"], float(r["value"][1]))) for r in sorted(json.load(sys.stdin)["data"]["result"], key=lambda r: r["metric"]["partition"])]'

banner "3. Remedy idea: salt the hot key (key = order-HOT#<n>) -> spreads, but per-key ordering is lost across salts"
kcli hash -partitions 6 'order-HOT#0' 'order-HOT#1' 'order-HOT#2' 'order-HOT#3' 'order-HOT#4' 'order-HOT#5' 'order-HOT#6' 'order-HOT#7'

banner "4. Drain"
cleanup
for i in $(seq 1 30); do l="$(kcli group -group order-processing-group | sed -n 's/.*total lag: \([0-9]*\).*/\1/p')"; [[ "${l:-1}" -lt 50 ]] && break; sleep 3; done
echo "lag after drain: $l"
lab_done
