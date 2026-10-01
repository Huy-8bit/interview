#!/usr/bin/env bash
# Consumer leaves / crashes / joins -> rebalances (eager vs cooperative vs KIP-848). Reuses lab 06.
exec "$(dirname "$0")/../../06_rebalancing/run.sh" "$@"
