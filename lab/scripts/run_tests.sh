#!/bin/sh
# Pause only the simulator; restore exactly the previously running container.
set -eu
traffic_id=$(docker compose ps --status running -q traffic-generator)
restore() { if [ -n "$traffic_id" ]; then docker start "$traffic_id" >/dev/null; fi; }
trap restore EXIT
trap 'exit 130' INT TERM
if [ -n "$traffic_id" ]; then docker stop "$traffic_id" >/dev/null; fi
for service in vehicle-service warranty-service inspection-service repair-service; do
  docker compose exec -T "$service" pytest -q tests
done
docker compose run --build --rm --no-deps toolbox pytest -q tests
