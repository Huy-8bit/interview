#!/usr/bin/env bash
# Produce test messages.
#   ./scripts/produce-test-message.sh                        # one OrderCreated through producer-service (HTTP)
#   ./scripts/produce-test-message.sh 1001 500 2             # user product quantity
#   ./scripts/produce-test-message.sh --topic t --key k --value v [--count N]   # raw record via kcli
source "$(dirname "$0")/lib.sh"
if [[ "${1:-}" == --* ]]; then
  kcli produce "${@/--/-}"
  exit 0
fi
user="${1:-1001}"; product="${2:-500}"; qty="${3:-2}"
banner "POST /orders user=$user product=$product quantity=$qty"
curl -s -X POST localhost:8000/orders -H 'content-type: application/json' \
  -d "{\"user_id\":$user,\"product_id\":$product,\"quantity\":$qty}"
