#!/usr/bin/env bash
# Print records with partition / offset / key.  Default: last records of `orders`.
#   ./scripts/consume-test-message.sh [topic] [max] [extra kcli flags...]
#   ./scripts/consume-test-message.sh orders-dlq 10 -headers
source "$(dirname "$0")/lib.sh"
topic="${1:-orders}"; max="${2:-10}"; shift $(( $# > 2 ? 2 : $# ))
kcli consume -topic "$topic" -from start -max "$max" "$@"
