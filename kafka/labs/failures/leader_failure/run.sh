#!/usr/bin/env bash
# Leader failure = kill -9 the broker leading orders P0 under load (reuses lab 11).
exec "$(dirname "$0")/../../11_broker_failure/run.sh" "$@"
