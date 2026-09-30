#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
evidence="$PWD/artifacts/observability/lag-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$evidence"
original_instances=$(docker compose ps --status running -q inspection-service | wc -l | tr -d ' ')
[ "$original_instances" -gt 0 ] || original_instances=1
restore() {
  echo '[lag-demo] Restore configured consumer delay, replica count and normal traffic'
  docker compose stop traffic-generator >/dev/null || true
  docker compose up -d --no-deps --scale "inspection-service=$original_instances" inspection-service || true
  docker compose up -d --no-deps traffic-generator || true
}
trap restore EXIT
trap 'exit 130' INT TERM
probe() {
  docker compose run --rm --no-deps --user "$(id -u):$(id -g)" -v "$evidence:/evidence" toolbox python scripts/lag_probe.py "$@"
}
echo '[lag-demo 1/5] Prepare images and one consumer with 500ms delay'
docker compose build toolbox inspection-service traffic-generator
docker compose stop traffic-generator
SIMULATE_CONSUMER_DELAY_MS=500 docker compose up -d --no-deps --scale inspection-service=1 inspection-service
echo '[lag-demo 2/5] Start bounded REST producer (300s or 1000 vehicles maximum)'
LOAD_TEST_MODE=true LOAD_TEST_DURATION_SECONDS=300 LOAD_TEST_MAX_VEHICLES=1000 VIRTUAL_USERS=4 TRAFFIC_INTERVAL_MS=1800 docker compose up -d --no-deps traffic-generator
probe sample --members 1 --duration 90 --output /evidence/single.json
echo '[lag-demo 3/5] Scale to three consumers; preserve same group and 500ms delay'
SIMULATE_CONSUMER_DELAY_MS=500 docker compose up -d --no-deps --scale inspection-service=3 inspection-service
probe sample --members 3 --duration 150 --output /evidence/scaled.json
echo '[lag-demo 4/5] Assert lag rise/fall, real assignments, throughput gain, ongoing REST workload'
probe verify --single /evidence/single.json --scaled /evidence/scaled.json --output /evidence/result.json
echo "[lag-demo 5/5] PASS. Evidence: $evidence"
