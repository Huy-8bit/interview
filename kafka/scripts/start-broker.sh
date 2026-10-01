#!/usr/bin/env bash
# Start a stopped broker and wait until it is healthy and its replicas are back in ISR.
#   ./scripts/start-broker.sh 1
source "$(dirname "$0")/lib.sh"
id="${1:?broker id 1|2|3}"
banner "Starting kafka-$id"
docker compose start "kafka-$id"
wait_healthy "kafka-$id" 180 && ok "kafka-$id healthy" || die "kafka-$id not healthy"
step "waiting for followers on kafka-$id to catch up (ISR full)"
if wait_isr_full 180; then ok "no under-replicated partitions"; else warn "still under-replicated partitions"; fi
