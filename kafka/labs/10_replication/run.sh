#!/usr/bin/env bash
# Lab 10 — RF=3 + min.insync.replicas=2 + acks.
#   1. one broker down          -> ISR=2 >= min ISR: acks=all still works
#   2. + 2nd replica OUT OF ISR  -> ISR=1 < min ISR: acks=all REFUSED (NOT_ENOUGH_REPLICAS), acks=1 accepted
#      (we block kafka-2's replication fetches with iptables: it stays a KRaft voter, so the controller keeps working)
#   3. two NODES down            -> KRaft quorum lost (1/3 voters): no controller, ISR frozen, acks=all times out
source "$(dirname "$0")/../lib.sh"
desc_orders() { KT_BROKER=kafka-1 kt kafka-topics --bootstrap-server kafka-1:29092 --describe --topic orders 2>/dev/null | tail -6 | cut -c1-110; }
# key lab10 -> orders P3 (preferred leader kafka-1)
try_produce() { docker compose exec -T toolbox sh -c "timeout -s KILL 25 kcli produce -topic orders -key lab10 -value acks-$1 -acks $1 -idempotent=$([[ "$1" == all ]] && echo true || echo false) -timeout 8s 2>&1 | grep -v 'kgo:' | head -1"; }
restore() {
  ./scripts/net-fault.sh clear 2 >/dev/null 2>&1 || true
  docker compose start kafka-2 kafka-3 >/dev/null 2>&1
  wait_healthy kafka-2 240 || warn "kafka-2 not healthy yet"
  wait_healthy kafka-3 240 || warn "kafka-3 not healthy yet"
  if wait_isr_full 420; then ok "ISR full again"; else warn "still under-replicated"; fi
}
trap restore EXIT

banner "0. Durability settings of orders"
kt kafka-configs --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --entity-type topics --entity-name orders 2>/dev/null | grep -oE "(min.insync.replicas|unclean.leader.election.enable)=[a-z0-9]+" | sort -u
desc_orders

banner "1. Stop kafka-3 (1 of 3 brokers down)"
docker compose stop kafka-3 >/dev/null 2>&1; sleep 3
desc_orders
r="$(try_produce all)"; echo "acks=all -> $r"
expect "acks=all still works with ISR=2 >= min.insync.replicas=2" bash -c "echo '$r' | grep -q '^produced'"

banner "2. kafka-2 stops replicating (iptables drops its fetches to the leaders); it stays a controller voter"
./scripts/net-fault.sh block-replication 2
try_produce 1 >/dev/null   # an acks=1 write to P3 makes kafka-2 fall behind on that partition
echo "waiting replica.lag.time.max.ms (10s) + margin for the leader to shrink the ISR ..."
sleep 18
desc_orders
echo "NOTE: only partitions that RECEIVED writes shrink: a follower whose log end offset equals the leader's is still 'caught up'."
echo "(Elr = Eligible Leader Replicas, KIP-966: replicas removed from the ISR while ISR < min ISR; they stay electable)"
ner() { curl -s localhost:7071/metrics | sed -n 's/^kafka_network_requestmetrics_errors_total{error="NOT_ENOUGH_REPLICAS",request="Produce"} \([0-9.]*\)/\1/p' | cut -d. -f1; }
n0="$(ner)"; n0="${n0:-0}"
r_all="$(try_produce all)"; echo "acks=all -> $r_all"
n1="$(ner)"; n1="${n1:-0}"
echo "broker kafka-1 answered NOT_ENOUGH_REPLICAS $((n1-n0)) times: the client retried (retriable error) until its 8s delivery timeout"
expect "acks=all REFUSED by the leader with NOT_ENOUGH_REPLICAS (durability over availability)" test "$((n1-n0))" -gt 0
expect "the producer surfaced a failure, not a success" bash -c "echo '$r_all' | grep -q ERROR"
r_one="$(try_produce 1)"; echo "acks=1   -> $r_one"
expect "acks=1 ACCEPTED: only ONE copy exists — lost if kafka-1 dies now" bash -c "echo '$r_one' | grep -q '^produced'"
curl -s localhost:7071/metrics | grep -E '^kafka_server_replicamanager_(underreplicatedpartitions|underminisrpartitioncount)'
./scripts/net-fault.sh clear 2
sleep 12; desc_orders

banner "3. Two NODES down (kafka-2 + kafka-3): the KRaft quorum (2 of 3 voters) is lost"
docker compose stop kafka-2 >/dev/null 2>&1; sleep 12
docker compose exec -T toolbox sh -c 'timeout -s KILL 15 kcli brokers 2>&1 | grep -E "ERROR|ACTIVE" | head -1'
curl -s localhost:7071/metrics | grep -E '^kafka_controller_kafkacontroller_activecontrollercount'
r_one="$(try_produce 1)"; echo "acks=1   -> $r_one"
r_all="$(try_produce all)"; echo "acks=all -> $r_all"
expect "no active controller: activecontrollercount=0" bash -c "curl -s localhost:7071/metrics | grep -q '^kafka_controller_kafkacontroller_activecontrollercount 0'"
expect "acks=all cannot complete (ISR cannot shrink without a controller)" bash -c "echo '$r_all' | grep -qiE 'timed out|NOT_ENOUGH'"

banner "4. Restore"
trap - EXIT
restore
desc_orders
r="$(try_produce all)"; echo "acks=all -> $r"
expect "acks=all works again" bash -c "echo '$r' | grep -q '^produced'"
lab_done
