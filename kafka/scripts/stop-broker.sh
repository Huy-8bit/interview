#!/usr/bin/env bash
# Stop one broker (graceful SIGTERM -> controlled shutdown). --kill = SIGKILL (crash).
#   ./scripts/stop-broker.sh 1 [--kill]
source "$(dirname "$0")/lib.sh"
id="${1:?broker id 1|2|3}"
if [[ "${2:-}" == "--kill" ]]; then
  banner "KILL -9 kafka-$id (no controlled shutdown: leaders move only after the session timeout)"
  docker compose kill -s KILL "kafka-$id"
else
  banner "Stopping kafka-$id (controlled shutdown: leaders are moved away first)"
  docker compose stop "kafka-$id"
fi
docker compose ps "kafka-$id" --format '{{.Service}} {{.Status}}'
