#!/usr/bin/env bash
exec "$(dirname "$0")/stop-broker.sh" 1 "$@"
