#!/usr/bin/env bash
# Inspect and replay a dead letter topic.
#   ./scripts/replay-dlq.sh                 # inspect orders-dlq, then replay pending records to retry-orders
#   ./scripts/replay-dlq.sh payments-dlq
#   ./scripts/replay-dlq.sh orders-dlq --dry-run | --to original | --key order-123
source "$(dirname "$0")/lib.sh"
dlq="${1:-orders-dlq}"; shift || true
banner "DLQ content: $dlq"
kcli dlq-inspect -dlq "$dlq"
banner "Replaying $dlq"
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) args+=(-dry-run) ;;
    --to) args+=(-to "$2"); shift ;;
    --key) args+=(-key "$2"); shift ;;
    --max) args+=(-max "$2"); shift ;;
    *) die "unknown flag $1" ;;
  esac
  shift
done
kcli dlq-replay -dlq "$dlq" "${args[@]}"
