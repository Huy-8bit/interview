#!/usr/bin/env bash
# Shared helpers for the lab scripts. Source it:  . "$(dirname "$0")/lib.sh"
# Everything runs through `docker compose exec`, so no local psql is required.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-ecommerce}"
PRIMARY_SERVICE="postgres-primary"
REPLICA_SERVICE="postgres-replica"

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""; C_RESET=""
fi

header() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RESET"; }
ok()     { printf '%s[OK]%s   %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()   { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail()   { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*"; }

# psql_on <service> [psql args...]   (unix socket inside the container, pretty output)
psql_on() {
  local service="$1"; shift
  docker compose exec -T "$service" psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"
}

# scalar_on <service> <sql>   -> prints a single value, no headers
scalar_on() {
  psql_on "$1" -tAq -c "$2"
}

require_running() {
  local service
  for service in "$@"; do
    if ! docker compose ps --status running --services 2>/dev/null | grep -qx "$service"; then
      fail "service '$service' is not running. Start the lab with: docker compose up -d --build"
      exit 1
    fi
  done
}
