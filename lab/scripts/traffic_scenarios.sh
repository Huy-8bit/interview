#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
evidence="${TRAFFIC_EVIDENCE_DIR:-$PWD/artifacts/traffic/scenarios-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$evidence"
[ ! -e "$evidence/fail-result.json" ] || { echo 'Choose a new evidence directory' >&2; exit 2; }
run() { docker compose run --rm --no-deps --user "$(id -u):$(id -g)" -v "$evidence:/evidence" toolbox python scripts/traffic_verify.py "$@"; }
docker compose build toolbox traffic-generator > "$evidence/build.log" 2>&1
for result in fail pass; do
  rate=0
  [ "$result" != fail ] || rate=1
  run watermark --output "/evidence/$result-offsets.json"
  docker compose run --rm --no-deps -e TRAFFIC_ENABLED=true -e TRAFFIC_MODE=scenario \
    -e "FAIL_INSPECTION_RATE=$rate" -e "DELETE_RATE=$rate" \
    -e DUPLICATE_REQUEST_RATE=1 -e TRAFFIC_ERROR_RATE=1 traffic-generator \
    > "$evidence/$result.jsonl" 2> "$evidence/$result-compose.log"
  run verify --state "/evidence/$result-offsets.json" --log "/evidence/$result.jsonl" --output "/evidence/$result-result.json"
done
echo "PASS: PASS/FAIL scenarios; evidence: $evidence"
