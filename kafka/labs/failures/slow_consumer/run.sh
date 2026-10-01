#!/usr/bin/env bash
# Slow consumer -> lag grows -> drains when capacity returns (reuses lab 17).
exec "$(dirname "$0")/../../17_backpressure/run.sh" "$@"
