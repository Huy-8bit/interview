#!/usr/bin/env bash
# RabbitMQ / Celery failure drills (CASE 1-7). Every stopped node or worker is
# restored on exit; evidence JSON lands in artifacts/rabbitmq/drills-*.
set -euo pipefail
cd "$(dirname "$0")/.."
evidence="$PWD/artifacts/rabbitmq/drills-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$evidence"
original_workers=$(docker compose ps --status running -q report-worker | wc -l | tr -d ' ')
[ "$original_workers" -gt 0 ] || original_workers=2
stopped_node=''
restore() {
  echo '[drills] Restore RabbitMQ nodes, workers and traffic pacing'
  if [ -n "$stopped_node" ]; then docker compose start "$stopped_node" >/dev/null || true; fi
  docker compose exec -T traffic-generator python -m traffic_generator.control --rps 0 >/dev/null 2>&1 || true
  docker compose up -d --no-deps --scale "report-worker=$original_workers" report-worker >/dev/null || true
}
trap restore EXIT
trap 'exit 130' INT TERM
probe() {
  docker compose run --rm --no-deps --user "$(id -u):$(id -g)" -v "$evidence:/evidence" toolbox python scripts/rabbitmq_probe.py "$@"
}
field() { python3 -c "import json,sys; v=json.load(open(sys.argv[1])); [v := v[k] for k in sys.argv[2:]]; print(v)" "$@"; }
cli() { docker compose exec -T inspection-service python -m app.reports.cli "$@"; }
workers() { REPORT_RENDER_COST_MS=${2:-300} docker compose up -d --no-deps --wait --scale "report-worker=$1" report-worker >/dev/null; }

docker compose build toolbox > "$evidence/build.log" 2>&1
probe snapshot --output /evidence/baseline.json >/dev/null

echo '== CASE 1: stop one RabbitMQ node (a follower of the work queue)'
leader=$(field "$evidence/baseline.json" work leader)
node=$(python3 -c "import json,sys; q=json.load(open(sys.argv[1]))['work']; print([m for m in q['members'] if m != q['leader']][-1].split('@')[1])" "$evidence/baseline.json")
echo "leader=$leader; stopping follower $node"
stopped_node=$node
docker compose stop "$node"
probe wait online 2 --timeout 60 --output /evidence/case1-degraded.json >/dev/null
probe sample --label case1-node-down --duration 30 --interval 10 --output /evidence/case1-processing.json | tail -n 4
docker compose start "$node"; stopped_node=''
probe wait online 3 --timeout 120 --output /evidence/case1-recovered.json >/dev/null
echo "CASE 1 OK: 2/3 members kept the quorum queue available; $node rejoined"

echo '== CASE 2: kill the work queue leader'
probe snapshot --output /evidence/case2-before.json >/dev/null
leader=$(field "$evidence/case2-before.json" work leader)
leader_service=${leader#rabbit@}
generated=$(field "$evidence/case2-before.json" generated_rows)
echo "killing leader $leader_service"
stopped_node=$leader_service
docker compose kill -s SIGKILL "$leader_service"
probe wait leader-changed "$leader" --timeout 60 --output /evidence/case2-election.json >/dev/null
echo "new leader: $(field "$evidence/case2-election.json" snapshot work leader)"
probe wait consumers "$original_workers" --timeout 90 --output /evidence/case2-reconnected.json >/dev/null
probe wait generated-above "$generated" --timeout 90 --output /evidence/case2-recovered.json >/dev/null
docker compose start "$leader_service"; stopped_node=''
probe wait online 3 --timeout 120 --output /evidence/case2-rejoined.json >/dev/null
echo "CASE 2 OK: election, workers reconnected ($original_workers consumers), tasks completing again"

echo '== CASE 3: kill the only worker while it renders a report'
workers 1 15000
probe wait processing --timeout 120 >/dev/null
probe processing --output /evidence/case3-in-flight.json >/dev/null
inspection=$(field "$evidence/case3-in-flight.json" inspection_id)
probe snapshot --output /evidence/case3-before.json >/dev/null
echo "worker killed while rendering inspection $inspection"
docker compose kill -s SIGKILL report-worker
workers 1
probe report "$inspection" --timeout 120 --output /evidence/case3-report.json >/dev/null
sleep 12  # one Prometheus scrape of the broker redelivery counter
probe snapshot --output /evidence/case3-after.json >/dev/null
python3 - "$evidence" <<'PY'
import json, sys
d = sys.argv[1]
report = json.load(open(f"{d}/case3-report.json"))
before, after = (json.load(open(f"{d}/case3-{n}.json")) for n in ("before", "after"))
assert report["attempts"] >= 2, report
assert report["events"] == 1, report
assert after["broker_redelivered_total"] > before["broker_redelivered_total"], (before["broker_redelivered_total"], after["broker_redelivered_total"])
print(f"CASE 3 OK: unacked task redelivered; attempts={report['attempts']}, one report, events={report['events']}")
PY

echo '== CASE 4: stop all workers while traffic keeps completing inspections'
docker compose exec -T traffic-generator python -m traffic_generator.control --rps "${DRILL_TRAFFIC_RPS:-35}" >/dev/null
docker compose stop report-worker >/dev/null
probe sample --label case4-no-workers --duration 60 --interval 10 --output /evidence/case4.json | tail -n 3

echo '== CASE 5 + 6: start one slow worker, then scale 1 -> 4'
workers 1 1000
probe sample --label case5-one-worker --duration 45 --interval 15 --output /evidence/case5.json | tail -n 2
workers 4 1000
probe sample --label case6-four-workers --duration 60 --interval 15 --output /evidence/case6.json | tail -n 2
docker compose exec -T traffic-generator python -m traffic_generator.control --rps 0 >/dev/null
python3 - "$evidence" <<'PY'
import json, sys
d = sys.argv[1]
c4, c5, c6 = (json.load(open(f"{d}/case{n}.json")) for n in (4, 5, 6))
assert c4["depth_end"] > c4["depth_start"], "queue depth did not rise without workers"
assert c6["throughput_per_second"] > c5["throughput_per_second"] * 2, (c5["throughput_per_second"], c6["throughput_per_second"])
print(f"CASE 4 OK: depth {c4['depth_start']} -> {c4['depth_end']} with 0 consumers")
print(f"CASE 5/6 OK: {c5['throughput_per_second']}/s with 1 worker -> {c6['throughput_per_second']}/s with 4; depth {c6['depth_max']} -> {c6['depth_end']}")
PY

echo '== CASE 7: a task that always fails -> retry, retry, retry -> DLQ; invalid input -> DLQ at once'
probe snapshot --output /evidence/case7-before.json >/dev/null
dlq=$(field "$evidence/case7-before.json" dlq ready)
cli submit --fault transient | tee "$evidence/case7-transient.json"
cli submit | tee "$evidence/case7-permanent.json"
probe wait dlq $((dlq + 2)) --timeout 120 --output /evidence/case7-dlq.json >/dev/null
task=$(field "$evidence/case7-transient.json" task_id)
docker compose logs --no-color report-worker | grep "$task" | grep -o '"message": "report_task_[a-z_]*"[^}]*"attempt": [0-9]*' | tee "$evidence/case7-attempts.log"
cli dlq --limit 50 > "$evidence/case7-dlq-records.json"
echo "CASE 7 OK: DLQ grew by 2; records in $evidence/case7-dlq-records.json"
echo "[drills] PASS. Evidence: $evidence"
