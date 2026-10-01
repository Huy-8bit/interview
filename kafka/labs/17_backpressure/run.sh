#!/usr/bin/env bash
# Lab 17 — producer 5000 msg/s, consumers ~1000 msg/s: the log absorbs the difference as LAG.
source "$(dirname "$0")/../lib.sh"
RATE="${RATE:-5000}"; SECS="${SECS:-30}"; DELAY_MS="${DELAY_MS:-5}"
CONSUMER_PORTS="8011 8012 8013 8025 8022 8023"
cleanup() {
  for p in 8011 8012 8013; do curl -s -X POST "localhost:$p/admin/delay?ms=0" >/dev/null; done
  for p in $CONSUMER_PORTS; do curl -s -X POST "localhost:$p/admin/log-every?n=1" >/dev/null; done
  curl -s -X POST localhost:8022/admin/log-every?n=100 >/dev/null
  curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null
}
trap cleanup EXIT
lag() { kcli group -group order-processing-group | sed -n 's/.*total lag: \([0-9]*\).*/\1/p'; }
prom() { curl -s -G localhost:9090/api/v1/query --data-urlencode "query=$1" | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print("%.1f" % float(r[0]["value"][1]) if r else "n/a")'; }

for p in $CONSUMER_PORTS; do curl -s -X POST "localhost:$p/admin/log-every?n=5000" >/dev/null; done
for p in 8011 8012 8013; do curl -s -X POST "localhost:$p/admin/delay?ms=$DELAY_MS" >/dev/null; done
echo "order-consumers: +${DELAY_MS}ms per record, 6 partitions processed in parallel => roughly 6 x 1000/(${DELAY_MS}+~1) records/s"

banner "1. Produce $RATE msg/s for ${SECS}s"
curl -s -X POST "localhost:8001/start?mode=constant&rate=$RATE&duration=${SECS}s" >/dev/null
peak=0
for i in $(seq 5 5 $((SECS+5))); do
  sleep 5; l="$(lag)"; (( l > peak )) && peak=$l
  printf "t=%3ss lag=%7s  produce=%7s/s  consume=%7s/s  e2e p95=%ss\n" "$i" "$l" \
    "$(prom 'sum(rate(produced_total{job="producer"}[15s]))')" \
    "$(prom 'sum(rate(consumed_total{group="order-processing-group"}[15s]))')" \
    "$(prom 'histogram_quantile(0.95, sum by (le) (rate(end_to_end_latency_seconds_bucket{group="order-processing-group"}[15s])))')"
done
expect "lag grew while producers outpaced consumers (peak $peak)" test "$peak" -gt 20000

banner "2. Producer stopped: consumers keep draining at their own pace (the log is the buffer)"
for i in 1 2 3 4; do sleep 5; printf "lag=%7s  consume=%7s/s\n" "$(lag)" "$(prom 'sum(rate(consumed_total{group="order-processing-group"}[15s]))')"; done

banner "3. 'Scale' the consumers (remove the artificial delay) and watch the lag fall to ~0"
for p in 8011 8012 8013; do curl -s -X POST "localhost:$p/admin/delay?ms=0" >/dev/null; done
for i in $(seq 1 60); do
  sleep 5; l="$(lag)"
  printf "lag=%7s  consume=%7s/s\n" "$l" "$(prom 'sum(rate(consumed_total{group="order-processing-group"}[15s]))')"
  [[ "$l" -lt 100 ]] && break
done
expect "lag back to ~0 ($l)" test "$l" -lt 100
lab_done
