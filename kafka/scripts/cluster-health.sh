#!/usr/bin/env bash
# End-to-end health verification of the lab (not just "container is up").
#   ./scripts/cluster-health.sh
source "$(dirname "$0")/lib.sh"
PASS=0; FAILS=0
check() { # check "<description>" <command...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; PASS=$((PASS+1)); else fail "$d"; FAILS=$((FAILS+1)); fi
}

banner "1. Containers"
for s in kafka-1 kafka-2 kafka-3 kafka-ui schema-registry redis prometheus grafana producer-service \
         order-consumer-1 order-consumer-2 order-consumer-3 payment-consumer analytics-consumer \
         notification-consumer txn-processor traffic-generator lag-exporter toolbox; do
  st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$(cid "$s")" 2>/dev/null || echo missing)"
  check "$s is $st" test "$st" = healthy
done

banner "2. Brokers registered + KRaft quorum"
brokers_out="$(kcli brokers)"
echo "$brokers_out"
n="$(echo "$brokers_out" | awk '/^NODE/{f=1;next} f&&/^[0-9]+ /{c++} /^$/{f=0} END{print c+0}')"
check "3 brokers registered in metadata (got $n)" test "$n" = 3
leader="$(echo "$brokers_out" | sed -n 's/.*ACTIVE CONTROLLER = node \([0-9]*\).*/\1/p')"
check "KRaft quorum has an active controller (node ${leader:-none})" test -n "$leader"
voters="$(echo "$brokers_out" | awk '/^VOTER/{f=1;next} f&&NF==4{c++; if($4>100) bad++} END{print c+0, bad+0}')"
check "3 voters, none lagging > 100 records ($voters)" test "$voters" = "3 0"

banner "3. Topics from kafka/topics/topics.conf"
desc="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe 2>/dev/null)"
while read -r topic parts rf _; do
  [[ -z "$topic" || "$topic" == \#* ]] && continue
  line="$(echo "$desc" | grep -E "^Topic: $topic	" || true)"
  p="$(echo "$line" | sed -n 's/.*PartitionCount: \([0-9]*\).*/\1/p')"
  r="$(echo "$line" | sed -n 's/.*ReplicationFactor: \([0-9]*\).*/\1/p')"
  check "topic $topic partitions=$parts rf=$rf (actual ${p:-?}/${r:-?})" test "$p/$r" = "$parts/$rf"
done < kafka/topics/topics.conf

banner "4. Partition health"
urp="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --under-replicated-partitions 2>/dev/null | grep -c Partition: || true)"
off="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --unavailable-partitions 2>/dev/null | grep -c Partition: || true)"
umi="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --under-min-isr-partitions 2>/dev/null | grep -c Partition: || true)"
check "no under-replicated partitions (ISR == replicas) [$urp]" test "$urp" = 0
check "no offline partitions [$off]" test "$off" = 0
check "no partitions under min ISR [$umi]" test "$umi" = 0
dist="$(kcli topics | tail -1)"
echo "    $dist"
check "leaders spread over all 3 brokers" bash -c "echo '$dist' | grep -q kafka-1= && echo '$dist' | grep -q kafka-2= && echo '$dist' | grep -q kafka-3="

banner "5. Consumer groups"
groups="$(kcli groups)"; echo "$groups"
for g in order-processing-group payment-group analytics-group notification-group; do
  check "group $g is Stable" bash -c "echo '$groups' | grep -E '^$g ' | grep -q Stable"
done

banner "6. Host access + observability"
for p in 9092 9093 9094; do check "host port localhost:$p reachable" nc -z localhost "$p"; done
check "Kafka UI      http://localhost:8080" curl -sf localhost:8080/actuator/health
check "Grafana       http://localhost:3000" curl -sf localhost:3000/api/health
check "Prometheus    http://localhost:9090" curl -sf localhost:9090/-/ready
up="$(curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=count(up{job=~"kafka-broker|lag-exporter|producer"}==1)' | sed -n 's/.*"value":\[[^,]*,"\([0-9]*\)".*/\1/p')"
check "Prometheus scrapes brokers + lag-exporter + producers (6 targets up, got ${up:-0})" test "${up:-0}" = 6
check "Schema Registry http://localhost:8081" curl -sf localhost:8081/subjects

echo
if (( FAILS == 0 )); then ok "cluster-health: $PASS checks passed"; else fail "cluster-health: $FAILS failed, $PASS passed"; exit 1; fi
