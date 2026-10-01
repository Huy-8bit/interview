#!/usr/bin/env bash
# Safe Go alternative: empty DB only, never reset/drop/truncate existing data.
# ./scripts/generate-data-go.sh 5m --dry-run
# ./scripts/generate-data-go.sh --local 5m --dry-run --workers 4
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
local_run=0
if [ "${1:-}" = "--local" ]; then local_run=1; shift; fi
if [ "$local_run" -eq 1 ]; then
  # Match the existing scripts' .env loading convention.
  if [ -f .env ]; then set -a; . ./.env; set +a; fi
  export DB_HOST="${DB_HOST:-localhost}" DB_PORT="${DB_PORT:-${PRIMARY_PORT:-5432}}"
  export DB_NAME="${DB_NAME:-${POSTGRES_DB:-ecommerce}}" DB_USER="${DB_USER:-${POSTGRES_USER:-postgres}}"
  export DB_PASSWORD="${DB_PASSWORD:-${POSTGRES_PASSWORD:-postgres}}"
  cd data-generator-go
  exec go run . "$@"
fi
# --no-deps avoids starting/recreating PostgreSQL or the old Python generator.
# The Go service is opt-in and absent from a normal compose up.
exec docker compose -f docker-compose.yml -f docker-compose.go.yml \
  run --build --rm --no-deps data-generator-go "$@"
