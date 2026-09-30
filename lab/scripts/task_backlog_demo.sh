#!/usr/bin/env bash
# Mandatory RabbitMQ backlog demo: inspections produce report tasks faster than one
# slow worker renders them, the quorum queue grows, then 4 workers drain it.
set -euo pipefail
cd "$(dirname "$0")/.."
evidence="$PWD/artifacts/rabbitmq/backlog-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$evidence"
render_ms=${BACKLOG_RENDER_COST_MS:-1000}
# Measured: ~0.08 report tasks per HTTP request, so 35 req/s ~= 2.8 tasks/s:
# above 1 slow worker (1/s), below 4 workers (4/s).
traffic_rps=${BACKLOG_TRAFFIC_RPS:-35}
original_workers=$(docker compose ps --status running -q report-worker | wc -l | tr -d ' ')
[ "$original_workers" -gt 0 ] || original_workers=2
restore() {
  echo "[backlog-demo] Restore traffic pacing, render cost and $original_workers workers"
  docker compose exec -T traffic-generator python -m traffic_generator.control --rps 0 >/dev/null 2>&1 || true
  docker compose up -d --no-deps --scale "report-worker=$original_workers" report-worker >/dev/null || true
}
trap restore EXIT
trap 'exit 130' INT TERM
probe() {
  docker compose run --rm --no-deps --user "$(id -u):$(id -g)" -v "$evidence:/evidence" toolbox python scripts/rabbitmq_probe.py "$@"
}
docker compose build toolbox > "$evidence/build.log" 2>&1
echo "[backlog-demo 1/5] One worker, concurrency 1, ${render_ms}ms per report (~$((1000 / render_ms)) task/s capacity)"
REPORT_RENDER_COST_MS=$render_ms docker compose up -d --no-deps --wait --scale report-worker=1 report-worker
echo "[backlog-demo 2/5] Traffic at ${traffic_rps} HTTP req/s: every completed inspection enqueues one report task"
docker compose exec -T traffic-generator python -m traffic_generator.control --rps "$traffic_rps"
probe sample --label growing --duration "${BACKLOG_GROW_SECONDS:-90}" --interval 10 --output /evidence/growing.json
echo '[backlog-demo 3/5] Scale to 4 workers with the same render cost and the same traffic'
REPORT_RENDER_COST_MS=$render_ms docker compose up -d --no-deps --wait --scale report-worker=4 report-worker
probe sample --label draining --duration "${BACKLOG_DRAIN_SECONDS:-120}" --interval 10 --output /evidence/draining.json
echo '[backlog-demo 4/5] Assert: depth grew, then fell; completions/s increased with workers'
probe verify-backlog --growing /evidence/growing.json --draining /evidence/draining.json --output /evidence/result.json
echo "[backlog-demo 5/5] PASS. Grafana: RabbitMQ / Background Tasks -> Queue Depth. Evidence: $evidence"
