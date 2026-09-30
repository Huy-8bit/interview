#!/bin/sh
# Controlled node failures; all stopped nodes and one Repair instance are restored.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
evidence="${CLUSTER_EVIDENCE_DIR:-$project_dir/artifacts/cluster-drills/$(date +%Y%m%d-%H%M%S)}"
[ ! -e "$evidence/baseline.json" ] || { echo 'Use a new evidence directory for each run' >&2; exit 2; }
mkdir -p "$evidence"
stopped_node=''
observer=''
scaled=0
run() { docker compose run --rm --no-deps --user "$(id -u):$(id -g)" -v "$evidence:/evidence" toolbox python scripts/cluster_verify.py "$@"; }
restore() {
  if [ -n "$stopped_node" ]; then docker compose start "$stopped_node"; fi
  if [ -n "$observer" ]; then docker rm -f "$observer" >/dev/null 2>&1 || true; fi
  if [ "$scaled" -eq 1 ]; then docker compose up -d --no-deps --scale repair-service=1 repair-service; fi
}
trap restore EXIT
trap 'exit 130' INT TERM
docker compose build toolbox > "$evidence/build.log" 2>&1
run verify --members 1 --output /evidence/baseline.json > "$evidence/baseline.log"
observe_failure() {
  kind="$1"
  node="$2"
  label="$3"
  case "$node" in kafka-[123]|redis-[123456]) ;; *) echo "Unexpected node: $node" >&2; exit 2;; esac
  mkdir -p "$evidence/$label"
  observer="vehicle-cluster-probe-$(date +%s)-$label"
  docker compose run -d --no-deps --name "$observer" --user "$(id -u):$(id -g)" \
    -v "$evidence:/evidence" toolbox python scripts/cluster_verify.py "watch-$kind" \
    --node "$node" --directory "/evidence/$label" >/dev/null
  ready=0
  for attempt in $(seq 1 120); do
    if [ -f "$evidence/$label/ready.json" ]; then ready=1; break; fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$observer")" != true ]; then docker logs "$observer"; exit 1; fi
    sleep 1
  done
  [ "$ready" -eq 1 ] || { echo 'Observer startup timed out' >&2; exit 1; }
  stopped_node="$node"
  # stop -t 0 forces SIGKILL and prevents the restart policy from masking the outage.
  docker compose stop -t 0 "$node"
  touch "$evidence/$label/go"
  exit_code=$(docker wait "$observer")
  docker logs "$observer" > "$evidence/$label/observer.log" 2>&1
  docker rm "$observer" >/dev/null
  observer=''
  [ "$exit_code" -eq 0 ] || { cat "$evidence/$label/observer.log"; exit 1; }
  if [ "$kind" = kafka ]; then
    run verify --kafka-nodes 2 --output "/evidence/$label/down.json" > "$evidence/$label/down.log"
    if [ "$label" = kafka-controller ]; then
      live_broker=kafka-1
      [ "$node" != kafka-1 ] || live_broker=kafka-2
      docker compose exec -T "$live_broker" /opt/kafka/bin/kafka-metadata-quorum.sh \
        --bootstrap-server kafka-1:9092,kafka-2:9092,kafka-3:9092 describe --status \
        > "$evidence/$label/quorum-after-stop.txt"
      elected=$(awk '/^LeaderId:/ {print "kafka-" $2}' "$evidence/$label/quorum-after-stop.txt")
      case "$elected" in kafka-[123]) ;; *) echo 'No elected KRaft leader' >&2; exit 1;; esac
      [ "$elected" != "$node" ] || { echo 'KRaft leader did not change' >&2; exit 1; }
    fi
  else
    run verify --redis-degraded --output "/evidence/$label/down.json" > "$evidence/$label/down.log"
  fi
  run workflow --output "/evidence/$label/workflow.json" > "$evidence/$label/workflow.log"
  docker compose start "$node"
  stopped_node=''
  run verify --output "/evidence/$label/rejoined.json" > "$evidence/$label/rejoined.log"
  echo "PASS: $label ($node) - recovery, workflow and rejoin"
}
# MetadataResponse.controller_id is an admin forwarding broker in KRaft,
# not necessarily the active controller. DescribeQuorum is authoritative here.
docker compose exec -T kafka-1 /opt/kafka/bin/kafka-metadata-quorum.sh \
  --bootstrap-server kafka-1:9092,kafka-2:9092,kafka-3:9092 describe --status \
  > "$evidence/quorum-before.txt"
node=$(awk '/^LeaderId:/ {print "kafka-" $2}' "$evidence/quorum-before.txt")
observe_failure kafka "$node" kafka-controller
node=$(run select --kind kafka-leader)
observe_failure kafka "$node" kafka-partition-leader
node=$(run select --kind redis-replica)
observe_failure redis "$node" redis-replica
node=$(run select --kind redis-master)
observe_failure redis "$node" redis-master
scaled=1
docker compose up -d --no-deps --scale repair-service=3 repair-service
run verify --members 3 --output /evidence/repair-scaled.json > "$evidence/repair-scaled.log"
run workflow --output /evidence/scaled-workflow.json > "$evidence/scaled-workflow.log"
docker compose up -d --no-deps --scale repair-service=1 repair-service
scaled=0
run verify --members 1 --output /evidence/final.json > "$evidence/final.log"
trap - EXIT INT TERM
echo "PASS: consumer rebalance 1 -> 3 -> 1; evidence: $evidence"
