#!/usr/bin/env bash
# Host launcher: Docker/Compose and standard macOS/Linux shell tools only.
set -euo pipefail
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

startup_timeout=${STARTUP_TIMEOUT_SECONDS:-600}
case "$startup_timeout" in ''|*[!0-9]*|0) echo 'STARTUP_TIMEOUT_SECONDS must be a positive integer' >&2; exit 2;; esac
log_dir="$PWD/artifacts/startup/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$log_dir"
startup_log="$log_dir/startup.log"
step=0
started_at=$SECONDS
current_services=()

log() { printf '[%s] [%02d/13] %-7s %s\n' "$(date +%H:%M:%S)" "$step" "$1" "$2" | tee -a "$startup_log"; }
interrupted() {
  log STOP 'Startup interrupted; inspect running containers with docker compose ps --all.'
  exit 130
}
trap interrupted INT TERM

run_step() {
  step=$((step + 1))
  local title=$1 step_started=$SECONDS status
  shift
  log RUNNING "$title"
  if "$@" 2>&1 | tee -a "$startup_log"; then
    log OK "$title ($((SECONDS - step_started))s)"
  else
    status=$?
    log FAILED "$title (exit $status, $((SECONDS - step_started))s)"
    log LOG "$startup_log"
    docker compose ps --all || true
    if [ "${#current_services[@]}" -gt 0 ]; then
      printf 'Inspect: docker compose logs --tail=100'
      printf ' %s' "${current_services[@]}"
      printf '\n'
    fi
    exit "$status"
  fi
}

preflight() {
  command -v docker >/dev/null || { echo 'Install Docker and start Docker Desktop / Docker Engine.'; return 1; }
  docker info >/dev/null || { echo 'Docker Engine is not ready. Start Docker Desktop / Docker Engine first.'; return 1; }
  docker compose version || return
  docker compose up --help | grep -- --wait-timeout >/dev/null || { echo 'Update Docker Compose: --wait-timeout is required.'; return 1; }
  docker compose config --quiet
}

healthy_services() {
  docker compose up -d --build --no-deps --wait --wait-timeout "$startup_timeout" "$@"
}

# Init jobs must EXIT 0; running long-lived services must pass their healthcheck.
# Poll actual containers, never infer readiness from a fixed sleep.
await_containers() {
  local kind=$1 elapsed service ids id snapshot state code health all_ready
  local since=$SECONDS last_report=-10
  shift
  while :; do
    all_ready=1
    for service in "$@"; do
      ids=$(docker compose ps --all -q "$service") || return
      [ -n "$ids" ] || { echo "$service: container missing"; return 1; }
      for id in $ids; do
        snapshot=$(docker inspect --format '{{.State.Status}}|{{.State.ExitCode}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id") || return
        IFS='|' read -r state code health <<< "$snapshot"
        if [ "$state" = exited ]; then
          if [ "$code" -ne 0 ]; then
            echo "$service: FAILED (exit $code)"
            docker compose logs --no-color --tail=50 "$service" || true
            return 1
          fi
          # A traffic scenario intentionally exits once, unlike a continuous service.
          if [ "$kind" = job ]; then continue; fi
          if [ "$service" = traffic-generator ] && docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$id" | grep -x 'TRAFFIC_MODE=scenario' >/dev/null; then continue; fi
          echo "$service: unexpectedly exited"
          return 1
        fi
        if [ "$kind" = service ] && [ "$state" = running ] && { [ "$health" = healthy ] || [ "$health" = none ]; }; then continue; fi
        case "$state/$health" in dead/*|removing/*|*/unhealthy)
          echo "$service: FAILED ($state/$health)"
          docker compose logs --no-color --tail=50 "$service" || true
          return 1;;
        esac
        all_ready=0
        elapsed=$((SECONDS - since))
        if [ "$((elapsed - last_report))" -ge 10 ]; then
          echo "WAIT $service: state=$state, health=$health, elapsed=${elapsed}s"
        fi
      done
    done
    [ "$all_ready" -eq 0 ] || return 0
    elapsed=$((SECONDS - since))
    if [ "$((elapsed - last_report))" -ge 10 ]; then last_report=$elapsed; fi
    [ "$elapsed" -lt "$startup_timeout" ] || { echo "Timed out after ${startup_timeout}s waiting for: $*"; return 1; }
    sleep 2
  done
}

init_jobs() {
  local since
  since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  docker compose up -d --build --no-deps "$@" || return
  await_containers job "$@" || return
  docker compose logs --no-color --since "$since" "$@"
}

start_clients() {
  docker compose up -d --build --no-deps kafka-ui traffic-generator || return
  await_containers service kafka-ui traffic-generator || return
  echo 'Traffic status (enabled/mode/state/counters):'
  # docker cp also works after a successful one-shot scenario has exited.
  local id
  id=$(docker compose ps --all -q traffic-generator) || return
  docker cp "$id:/tmp/traffic-generator-status.json" "$log_dir/traffic-status.json" || return
  cat "$log_dir/traffic-status.json"
  printf '\n'
}

run_step 'Docker Engine, Compose and configuration' preflight
run_step 'Build application and traffic images' docker compose --progress plain build
current_services=(postgres-primary redis-1 redis-2 redis-3 redis-4 redis-5 redis-6 kafka-1 kafka-2 kafka-3 rabbitmq-1 rabbitmq-2 rabbitmq-3)
run_step 'PostgreSQL primary, 6 Redis nodes, 3 Kafka brokers, 3 RabbitMQ nodes' healthy_services "${current_services[@]}"
current_services=(postgres-init redis-cluster-init kafka-init rabbitmq-init)
run_step 'DB roles/slot, Redis Cluster, Kafka topics, RabbitMQ cluster and quorum queues' init_jobs "${current_services[@]}"
current_services=(postgres-replica)
run_step 'PostgreSQL replica healthcheck' healthy_services "${current_services[@]}"
current_services=(vehicle-service warranty-service inspection-service repair-service inspection-api)
run_step 'Migrations and readiness of 4 APIs' healthy_services "${current_services[@]}"
current_services=(report-worker)
run_step 'Celery report workers consuming the RabbitMQ quorum queue' healthy_services "${current_services[@]}"
current_services=(cdc-db-init)
run_step 'CDC grants, publications and replica identity' init_jobs "${current_services[@]}"
current_services=(debezium-connect)
run_step 'Debezium Connect REST readiness' healthy_services "${current_services[@]}"
current_services=(debezium-init)
run_step 'Register 4 connectors and wait for RUNNING tasks' init_jobs "${current_services[@]}"
current_services=(prometheus kafka-exporter redis-exporter postgres-exporter postgres-replica-exporter platform-exporter cadvisor)
run_step 'Prometheus and real infrastructure exporters' healthy_services "${current_services[@]}"
current_services=(kafka-ui traffic-generator)
run_step 'Kafka UI and Traffic Generator' start_clients
current_services=(grafana prometheus)
monitoring_ready() {
  healthy_services grafana || return
  local allow_stopped=false
  local traffic_id
  traffic_id=$(docker compose ps --all -q traffic-generator) || return
  if docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$traffic_id" | grep -x 'TRAFFIC_MODE=scenario' >/dev/null; then allow_stopped=true; fi
  docker compose exec -T -e "ALLOW_STOPPED_TRAFFIC=$allow_stopped" platform-exporter python check_targets.py
}
run_step 'Grafana provisioning and Prometheus targets UP' monitoring_ready
log READY "Startup completed in $((SECONDS - started_at))s. Log: $startup_log"
for service in vehicle-service warranty-service inspection-api repair-service kafka-ui debezium-connect rabbitmq-1 rabbitmq-2 rabbitmq-3 prometheus grafana; do
  port=8000
  path=/docs
  case "$service" in kafka-ui) port=8080; path=;; debezium-connect) port=8083; path=/connectors;; rabbitmq-*) port=15672; path=;; prometheus) port=9090; path=/targets;; grafana) port=3000; path=;; esac
  if address=$(docker compose port --index 1 "$service" "$port" 2>/dev/null); then
    printf '%-20s http://%s%s\n' "$service" "$address" "$path" | tee -a "$startup_log"
  fi
done
printf '\nNext: make traffic-logs | make traffic-status | make rabbitmq-status | make ps\n' | tee -a "$startup_log"
