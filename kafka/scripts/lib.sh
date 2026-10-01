#!/usr/bin/env bash
# Shared helpers for every script / lab. Source it:  source "$(dirname "$0")/lib.sh"
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$LAB_ROOT"

BOOTSTRAP_INTERNAL="kafka-1:29092,kafka-2:29092,kafka-3:29092"

if [[ -t 1 ]]; then
  C_BOLD=$'\e[1m'; C_GREEN=$'\e[32m'; C_RED=$'\e[31m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_RESET=$'\e[0m'
else
  C_BOLD=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_BLUE=""; C_RESET=""
fi

banner() { echo; echo "${C_BOLD}${C_BLUE}==> $*${C_RESET}"; }
step()   { echo "${C_BOLD}--- $*${C_RESET}"; }
ok()     { echo "${C_GREEN}[OK]${C_RESET} $*"; }
warn()   { echo "${C_YELLOW}[WARN]${C_RESET} $*"; }
fail()   { echo "${C_RED}[FAIL]${C_RESET} $*"; }
die()    { fail "$*"; exit 1; }

# Kafka CLI tools inside a running broker container (default kafka-1, override KT_BROKER=kafka-2)
kt() {
  local b="${KT_BROKER:-}"
  if [[ -z "$b" ]]; then
    for c in kafka-1 kafka-2 kafka-3; do
      if [[ "$(docker compose ps -q --status running "$c" 2>/dev/null)" != "" ]]; then b="$c"; break; fi
    done
  fi
  docker compose exec -T "$b" kt "$@"
}

# Go lab CLI inside the toolbox container
kcli() { docker compose exec -T toolbox kcli "$@"; }

redis_cli() { docker compose exec -T redis redis-cli "$@"; }

# container id of a compose service (for `docker run --network container:<id>`)
cid() { docker compose ps -q "$1"; }

wait_healthy() { # wait_healthy <service> [timeout_s]
  local svc="$1" t="${2:-120}" i=0
  while (( i < t )); do
    local st; st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$(cid "$svc")" 2>/dev/null || true)"
    [[ "$st" == "healthy" ]] && return 0
    sleep 2; i=$((i+2))
  done
  return 1
}

# Wait until no partition is under-replicated (all ISR full)
wait_isr_full() { # wait_isr_full [timeout_s]
  local t="${1:-120}" i=0
  while (( i < t )); do
    local n
    n="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --under-replicated-partitions 2>/dev/null | grep -c 'Partition:' || true)"
    [[ "$n" == "0" ]] && return 0
    sleep 3; i=$((i+3))
  done
  return 1
}

http_post() { curl -sf -X POST "$@"; }

# Run a command in the network namespace of a broker with NET_ADMIN (tc / iptables).
in_broker_netns() { # in_broker_netns <broker-service> <cmd...>
  local svc="$1"; shift
  docker run --rm --cap-add NET_ADMIN --network "container:$(cid "$svc")" kafka-lab/app:local "$@"
}
