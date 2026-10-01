#!/usr/bin/env bash
# Undo everything a lab may have changed, so the next lab starts clean.
#   ./scripts/reset-lab.sh          soft reset (keeps cluster + business data)
#   ./scripts/reset-lab.sh --hard   docker compose down -v && up --build (wipes ALL data)
#
# Soft reset:
#   1. start stopped brokers, unpause containers, clear tc/iptables faults
#   2. stop the extra consumers (profile "scale"), recreate services with default env
#   3. consumers: processing delay 0, log every record; traffic back to 5 msg/s
#   4. delete temporary lab topics + throwaway consumer groups
#   5. re-apply kafka/topics/topics.conf configs, purge retry / DLQ topics
#   6. flush Redis (idempotency keys, lab markers, failing products)
#   7. wait for full ISR and run a short health summary
source "$(dirname "$0")/lib.sh"

if [[ "${1:-}" == "--hard" ]]; then
  banner "HARD reset: removing containers AND volumes"
  docker compose --profile scale down -v --remove-orphans
  docker compose up -d --build
  exit 0
fi

TEMP_TOPICS="perf-p1 perf-p3 perf-p6 perf-p12 idempotence-demo large-messages orders-sr acks-demo"

banner "1. brokers + network faults"
for b in 1 2 3; do
  state="$(docker inspect -f '{{.State.Status}}' "$(cid kafka-$b)" 2>/dev/null || echo missing)"
  [[ "$state" == "paused" ]] && docker compose unpause "kafka-$b"
  [[ "$state" != "running" && "$state" != "paused" ]] && docker compose start "kafka-$b"
done
for b in 1 2 3; do wait_healthy "kafka-$b" 180 || warn "kafka-$b not healthy yet"; done
for b in 1 2 3; do in_broker_netns "kafka-$b" sh -c 'tc qdisc del dev eth0 root 2>/dev/null; iptables -F OUTPUT; true' >/dev/null 2>&1 || true; done
ok "brokers running, network rules cleared"

banner "2. services back to default configuration"
docker compose --profile scale stop order-consumer-4 order-consumer-5 order-consumer-6 order-consumer-7 order-consumer-8 >/dev/null 2>&1 || true
docker compose --profile scale rm -f order-consumer-4 order-consumer-5 order-consumer-6 order-consumer-7 order-consumer-8 >/dev/null 2>&1 || true
# Unset lab overrides that may still be exported in this shell
unset ORDER_COMMIT_MODE ORDER_BALANCER ORDER_GROUP_PROTOCOL ORDER_PROCESSING_DELAY_MS ORDER_MAX_RETRIES \
      PRODUCER_ACKS PRODUCER_IDEMPOTENT PRODUCER_COMPRESSION PRODUCER_LINGER_MS TRAFFIC_RATE_PER_SECOND TRAFFIC_MODE || true
docker compose up -d --remove-orphans 2>&1 | grep -E "Recreate|Started" || true
for s in order-consumer-1 order-consumer-2 order-consumer-3 traffic-generator producer-service; do wait_healthy "$s" 90 || warn "$s not healthy"; done
ok "services running with .env defaults"

banner "3. runtime knobs"
for p in 8011 8012 8013; do
  curl -sf -X POST "localhost:$p/admin/delay?ms=0" >/dev/null || true
  curl -sf -X POST "localhost:$p/admin/log-every?n=1" >/dev/null || true
done
curl -sf -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null && ok "traffic: constant 5 msg/s"

banner "4. temporary topics + throwaway groups"
existing="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --list 2>/dev/null)"
for t in $TEMP_TOPICS; do
  if grep -qx "$t" <<<"$existing"; then kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --delete --topic "$t" && echo "    deleted topic $t"; fi
done
for g in $(kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --list 2>/dev/null | grep -E '^(lab-|bench-|dlq-replayer-|console-)' || true); do
  kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --delete --group "$g" >/dev/null 2>&1 && echo "    deleted group $g" || warn "could not delete group $g (still active?)"
done

banner "5. topic configs + purge retry/DLQ"
docker compose run --rm kafka-init 2>&1 | grep -E "exists|create|ready" | sed 's/^/    /' | tail -3
json='{"version":1,"partitions":['
first=1
for t in retry-orders retry-payments orders-dlq payments-dlq; do
  for p in 0 1 2; do
    [[ $first == 1 ]] || json+=","
    json+="{\"topic\":\"$t\",\"partition\":$p,\"offset\":-1}"; first=0
  done
done
json+=']}'
echo "$json" | docker compose exec -T kafka-1 bash -c 'cat > /tmp/purge.json && kt kafka-delete-records --bootstrap-server kafka-1:29092 --offset-json-file /tmp/purge.json' >/dev/null \
  && ok "retry + DLQ topics purged (log start offset moved to the end)"

step "schema registry subjects created by labs"
for subj in orders-avro-value orders-sr-value; do
  curl -sf -X DELETE "localhost:8081/subjects/$subj" >/dev/null 2>&1 && curl -sf -X DELETE "localhost:8081/subjects/$subj?permanent=true" >/dev/null 2>&1 && echo "    deleted subject $subj" || true
done

banner "6. Redis"
redis_cli FLUSHALL >/dev/null && ok "redis flushed"

banner "7. waiting for full ISR"
wait_isr_full 180 && ok "all partitions fully replicated" || warn "under-replicated partitions remain"
kcli groups
ok "reset done"
