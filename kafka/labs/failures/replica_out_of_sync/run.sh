#!/usr/bin/env bash
# A follower that cannot fetch (replication port blocked) falls behind -> after replica.lag.time.max.ms
# (10s) the leaders remove it from the ISR (IsrShrinks). Writes continue (ISR=2 >= min ISR 2).
# Unblock -> it catches up -> IsrExpands.
source "$(dirname "$0")/../../lib.sh"
trap './scripts/net-fault.sh clear 3 >/dev/null 2>&1; curl -s -X POST "localhost:8001/start?mode=constant&rate=5&duration=0s" >/dev/null' EXIT
shr() { for p in 7071 7072; do curl -s localhost:$p/metrics | sed -n 's/^kafka_server_replicamanager_isrshrinks_total \([0-9.]*\)/\1/p'; done | awk '{s+=$1} END{print s+0}'; }
curl -s -X POST "localhost:8001/start?mode=constant&rate=100&duration=0s" >/dev/null
s0="$(shr)"
./scripts/net-fault.sh block-replication 3
sleep 20
kcli topics -topic orders | tail -9
s1="$(shr)"; echo "ISR shrinks on kafka-1/kafka-2: $s0 -> $s1"
expect "leaders shrank the ISR" test "${s1%.*}" -gt "${s0%.*}"
r="$(docker compose exec -T toolbox sh -c 'timeout -s KILL 20 kcli produce -topic orders -key x -value y -timeout 8s 2>&1 | grep -v kgo: | head -1')"; echo "acks=all -> $r"
expect "acks=all still works with ISR={leader + 1 follower}" bash -c "echo '$r' | grep -q ^produced"
./scripts/net-fault.sh clear 3
wait_isr_full 120 && ok "kafka-3 caught up, ISR expanded"
kcli topics -topic orders | tail -9
lab_done
