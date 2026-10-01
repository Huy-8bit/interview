#!/usr/bin/env bash
# Poison / malformed messages -> retry -> DLQ -> replay (reuses lab 09).
exec "$(dirname "$0")/../../09_retry_dlq/run.sh" "$@"
