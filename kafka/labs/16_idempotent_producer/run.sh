#!/usr/bin/env bash
# Lab 16 — producer retries create duplicates unless the producer is idempotent.
# Recipe for a "lost ack": the leader appends the batch, but its RESPONSE is delayed (tc netem)
# beyond the client's request timeout (1s) -> the client gives up on that request and RETRIES
# a batch the broker already has.
source "$(dirname "$0")/../lib.sh"
T=idempotence-demo
cleanup() { [[ -n "${L:-}" ]] && ./scripts/net-fault.sh clear "${L#kafka-}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

existing="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --list 2>/dev/null)"
grep -qx "$T" <<<"$existing" || kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --create --topic $T --partitions 1 --replication-factor 3 --config min.insync.replicas=2 >/dev/null
sleep 2
L="$(kcli topics -topic $T | awk -v t=$T '$1==t{print $3}')"
echo "leader of $T-0 = $L (responses from $L to the toolbox container will be delayed)"

run_case() { # run_case <true|false>
  local out=/tmp/lab16-$1.txt
  docker compose exec -T toolbox kcli idempotence-test -topic $T -records 400 -idempotent="$1" -request-timeout 1s > "$out" 2>&1 &
  local pid=$!
  sleep 0.7
  ./scripts/net-fault.sh delay-to "${L#kafka-}" toolbox 1500ms >/dev/null
  sleep 3
  ./scripts/net-fault.sh clear "${L#kafka-}" >/dev/null
  wait $pid || true
  grep -vE "kgo:" "$out"
}

banner "A. idempotent=false (enable.idempotence=false): retries can duplicate"
a="$(run_case false)"; echo "$a"
da="$(echo "$a" | sed -n 's/.*DUPLICATES=\([0-9]*\).*/\1/p')"
expect "duplicates appeared without idempotence ($da)" test "${da:-0}" -gt 0

banner "B. idempotent=true: same fault, broker drops the retried batches (same PID + sequence)"
b="$(run_case true)"; echo "$b"
db="$(echo "$b" | sed -n 's/.*DUPLICATES=\([0-9]*\).*/\1/p')"
expect "no duplicates with the idempotent producer ($db)" test "${db:-1}" = 0

banner "C. What the broker stores: producerId + sequence numbers per batch"
seg="$(docker compose exec -T "$L" sh -c "ls /var/lib/kafka/data/$T-0/*.log | tail -1")"
KT_BROKER="$L" kt kafka-dump-log --files "$seg" 2>/dev/null | grep baseOffset | tail -4 | sed -E 's/partitionLeaderEpoch.*//' | cut -c1-150
lab_done
