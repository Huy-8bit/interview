#!/bin/sh
# Run only against this disposable lab stack. Every stopped container is restored.
set -eu
component="${1:-kafka}"
case "$component" in postgres|redis|kafka|warranty-service) ;; *) echo 'Usage: sh scripts/outage_drills.sh postgres|redis|kafka|warranty-service' >&2; exit 2;; esac
docker compose build toolbox
case "$component" in
  postgres) nodes="postgres-primary" ;;
  kafka) nodes="kafka-1 kafka-2 kafka-3" ;;
  redis) nodes="redis-1 redis-2 redis-3 redis-4 redis-5 redis-6" ;;
  *) nodes="$component" ;;
esac
restore() { docker compose start $nodes; }
trap restore EXIT
trap 'exit 130' INT TERM
docker compose stop $nodes
docker compose run --rm --no-deps toolbox python scripts/outage_probe.py "$component"
restore
trap - EXIT INT TERM
docker compose run --rm --no-deps toolbox python scripts/outage_probe.py recovery
