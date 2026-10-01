#!/usr/bin/env bash
# Hot key -> hot partition -> consumer imbalance (reuses lab 12).
exec "$(dirname "$0")/../../12_hot_partition/run.sh" "$@"
