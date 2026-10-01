#!/usr/bin/env bash
# Consumer lag = log end offset (high watermark) - committed offset.
#   ./scripts/consumer-lag.sh                       # total lag per group
#   ./scripts/consumer-lag.sh order-processing-group [--watch]
source "$(dirname "$0")/lib.sh"
group="${1:-}"
if [[ -z "$group" ]]; then kcli groups; exit 0; fi
if [[ "${2:-}" == "--watch" ]]; then
  docker compose exec toolbox kcli group -group "$group" -watch 2s
else
  kcli group -group "$group"
fi
