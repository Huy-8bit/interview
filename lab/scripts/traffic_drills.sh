#!/bin/sh
# External test orchestration, never invoked by the traffic-generator process.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
evidence="${TRAFFIC_EVIDENCE_DIR:-$PWD/artifacts/traffic/outages-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$evidence"
[ ! -e "$evidence/baseline.json" ] || { echo 'Choose a new evidence directory' >&2; exit 2; }
stopped=''
restore() { if [ -n "$stopped" ]; then docker start "$(docker compose ps -aq "$stopped")" >/dev/null; fi; }
trap restore EXIT
trap 'exit 130' INT TERM
docker compose exec -T traffic-generator cat /tmp/traffic-generator-status.json > "$evidence/baseline.json"
baseline_run=$(docker compose exec -T traffic-generator python -c 'import json; print(json.load(open("/tmp/traffic-generator-status.json"))["run_id"])')
progress() { docker compose exec -T traffic-generator python -m traffic_generator.check_progress "$1" --timeout 110 --run-id "$baseline_run"; }
progress flows_completed > "$evidence/warmup.json"
for kind in kafka-leader redis-master postgres-replica debezium-connect warranty-service; do
  case "$kind" in
    kafka-leader|redis-master) node=$(docker compose run --rm --no-deps toolbox python scripts/cluster_verify.py select --kind "$kind") ;;
    *) node="$kind" ;;
  esac
  stopped="$node"
  docker compose stop -t 0 "$node"
  # Keep infrastructure down long enough to cross the Redis election timeout
  # and observe multiple new requests, rather than just an in-flight completion.
  if [ "$kind" != warranty-service ]; then sleep 10; fi
  if [ "$kind" = warranty-service ]; then
    progress flows_failed > "$evidence/$kind-down.json"
    progress created_vehicles > "$evidence/$kind-continued.json"
  elif [ "$kind" = debezium-connect ]; then
    progress created_vehicles > "$evidence/$kind-down.json"
    # New inspections wait for warranty CDC. Full flow resumes after Connect recovery.
  elif [ "$kind" = postgres-replica ]; then
    progress replica_fallback_reads > "$evidence/$kind-down.json"
  else
    progress flows_completed > "$evidence/$kind-down.json"
  fi
  restore
  stopped=''
  progress flows_completed > "$evidence/$kind-recovered.json"
  echo "PASS: traffic remained alive during $kind and completed flows after recovery"
done
docker compose run --rm --no-deps toolbox python scripts/postgres_cdc_verify.py verify > "$evidence/database-final.log"
docker compose run --rm --no-deps toolbox python scripts/cluster_verify.py verify --members 1 > "$evidence/clusters-final.json"
docker compose exec -T traffic-generator cat /tmp/traffic-generator-status.json > "$evidence/final.json"
docker compose logs --no-log-prefix --tail=1500 traffic-generator > "$evidence/traffic.jsonl" 2>&1
trap - EXIT INT TERM
echo "PASS: traffic outages; evidence: $evidence"
