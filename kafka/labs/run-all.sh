#!/usr/bin/env bash
# Runs every lab in order with a soft reset in between and prints a PASS/FAIL table.
#   ./labs/run-all.sh                 (~45-60 min)
#   ./labs/run-all.sh 04_ordering 09_retry_dlq
cd "$(dirname "$0")/.."
LABS=("$@")
if [[ ${#LABS[@]} -eq 0 ]]; then
  LABS=(01_producer_consumer 02_partitions 03_message_key 04_ordering 05_consumer_group 06_rebalancing 07_offsets
        08_delivery_semantics 09_retry_dlq 10_replication 11_broker_failure 12_hot_partition 13_retention 14_compaction
        15_transactions 16_idempotent_producer 17_backpressure 18_large_messages 19_schema_evolution 20_observability
        failures/broker_failure failures/producer_restart failures/network_delay failures/replica_out_of_sync performance)
fi
mkdir -p /tmp/kafka-lab-runs
declare -a RESULTS
for l in "${LABS[@]}"; do
  log="/tmp/kafka-lab-runs/$(echo "$l" | tr / _).log"
  start=$(date +%s)
  echo "=== $l"
  if bash "labs/$l/run.sh" > "$log" 2>&1; then r=PASS; else r=FAIL; fi
  RESULTS+=("$(printf '%-34s %s  %4ss  %s' "$l" "$r" "$(( $(date +%s) - start ))" "$log")")
  echo "    $r"
  ./scripts/reset-lab.sh > /tmp/kafka-lab-runs/reset-after-$(echo "$l" | tr / _).log 2>&1 || echo "    reset failed"
done
echo; printf '%s\n' "${RESULTS[@]}"
