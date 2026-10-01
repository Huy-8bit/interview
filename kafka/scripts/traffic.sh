#!/usr/bin/env bash
# Control the traffic-generator.
#   ./scripts/traffic.sh status
#   ./scripts/traffic.sh stop
#   ./scripts/traffic.sh constant 1000 60s
#   ./scripts/traffic.sh burst 100 120s 10000 10s        # base rate, duration, burst rate, burst length
#   ./scripts/traffic.sh skewed 2000 60s 0.8              # 80% of records share one key
#   ./scripts/traffic.sh default                          # back to the background 5 msg/s
source "$(dirname "$0")/lib.sh"
TG=localhost:8001
case "${1:-status}" in
  status)   curl -s $TG/status ;;
  stop)     curl -s -X POST $TG/stop ;;
  constant) curl -s -X POST "$TG/start?mode=constant&rate=${2:-1000}&duration=${3:-60s}" ;;
  burst)    curl -s -X POST "$TG/start?mode=burst&rate=${2:-100}&duration=${3:-120s}&burst_rate=${4:-10000}&burst_duration=${5:-10s}&burst_interval=${6:-30s}" ;;
  skewed)   curl -s -X POST "$TG/start?mode=skewed-key&rate=${2:-2000}&duration=${3:-60s}&hot_ratio=${4:-0.8}" ;;
  default)  curl -s -X POST "$TG/start?mode=constant&rate=5&duration=0s" ;;
  *) die "usage: traffic.sh status|stop|constant|burst|skewed|default" ;;
esac
