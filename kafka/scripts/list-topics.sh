#!/usr/bin/env bash
# List topics (add --internal to include __consumer_offsets, __transaction_state, ...)
source "$(dirname "$0")/lib.sh"
if [[ "${1:-}" == "--internal" ]]; then
  kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --list
else
  kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --list --exclude-internal
fi
