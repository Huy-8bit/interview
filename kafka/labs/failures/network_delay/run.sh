#!/usr/bin/env bash
# 200ms extra latency on every packet leaving kafka-1 (tc netem) under 200 msg/s:
# acks=all produce latency rises (replication + responses), throughput holds, ISR stays (lag < 10s).
source "$(dirname "$0")/../../lib.sh"
trap './scripts/net-fault.sh clear 1 >/dev/null 2>&1; curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null' EXIT
p99() { curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=histogram_quantile(0.99, sum by (le) (rate(produce_latency_seconds_bucket{instance=~"traffic-generator.*"}[20s])))' | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print("%.3f" % float(r[0]["value"][1]) if r else "n/a")'; }
curl -s -X POST "localhost:8001/start?mode=constant&rate=200&duration=0s" >/dev/null
sleep 25; base="$(p99)"; echo "produce p99 before: ${base}s"
./scripts/net-fault.sh delay 1 200ms
sleep 25; slow="$(p99)"; echo "produce p99 with 200ms on kafka-1: ${slow}s"
expect "latency increased under network delay" python3 -c "import sys; sys.exit(0 if float('$slow') > float('$base') else 1)"
kcli topics -topic orders | tail -1
./scripts/net-fault.sh clear 1
sleep 25; echo "produce p99 after clearing: $(p99)s"
lab_done
