#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
evidence="${POSTGRES_EVIDENCE_DIR:-$project_dir/artifacts/postgres-cdc/$(date +%Y%m%d-%H%M%S)}"
[ ! -e "$evidence/baseline.json" ] || { echo 'Choose a new evidence directory' >&2; exit 2; }
mkdir -p "$evidence"
stopped=''
paused=0
run() { docker compose run --rm --no-deps --user "$(id -u):$(id -g)" -v "$evidence:/evidence" toolbox python scripts/postgres_cdc_verify.py "$@"; }
resume_replay() { docker compose exec -T postgres-replica psql -U platform_admin -d postgres -c 'SELECT pg_wal_replay_resume()'; }
restore() {
  if [ -n "$stopped" ]; then docker compose start "$stopped"; fi
  if [ "$paused" -eq 1 ]; then resume_replay; fi
}
trap restore EXIT
trap 'exit 130' INT TERM
docker compose build toolbox > "$evidence/build.log" 2>&1
run verify --output /evidence/baseline.json
run cdc --output /evidence/insert-update-delete.json
run workflow --output /evidence/four-database-workflow.json
stopped=postgres-replica
docker compose stop "$stopped"
run replica-down --output /evidence/replica-down.json
docker compose start "$stopped"
stopped=''
run verify --output /evidence/replica-rejoined.json
run watermark --output /evidence/connect-watermark.json
stopped=debezium-connect
docker compose stop "$stopped"
run changes --output /evidence/connect-down-changes.json
docker compose exec -T postgres-primary psql -d postgres -c "SELECT slot_name,active,restart_lsn,confirmed_flush_lsn,pg_wal_lsn_diff(pg_current_wal_lsn(),restart_lsn) AS retained_bytes FROM pg_replication_slots" > "$evidence/connect-down-slots.txt"
docker compose start "$stopped"
stopped=''
run resume --state /evidence/connect-watermark.json --changes /evidence/connect-down-changes.json --output /evidence/connect-resumed.json
run primary-prepare --output /evidence/primary-row.json
stopped=postgres-primary
docker compose stop "$stopped"
run primary-down --state /evidence/primary-row.json --output /evidence/primary-down.json
docker compose logs --tail=100 debezium-connect > "$evidence/connect-primary-outage.log" 2>&1
docker compose start "$stopped"
stopped=''
run verify --output /evidence/primary-restarted.json
run cdc --output /evidence/cdc-after-primary-restart.json
paused=1
docker compose exec -T postgres-replica psql -U platform_admin -d postgres -c 'SELECT pg_wal_replay_pause()'
run lag --output /evidence/lag.json
resume_replay
paused=0
run caught-up --state /evidence/lag.json --output /evidence/lag-recovered.json
run workflow --output /evidence/final-workflow.json
run verify --output /evidence/final.json
trap - EXIT INT TERM
echo "PASS: PostgreSQL replication, read fallback, lag, CDC and recovery; evidence: $evidence"
