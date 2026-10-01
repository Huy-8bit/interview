#!/usr/bin/env bash
# Lab 02 — Topic -> partitions -> replicas -> files on disk.
source "$(dirname "$0")/../lib.sh"

banner "1. orders: 6 partitions, RF=3. Who leads what?"
kcli topics -topic orders

banner "2. Partition count is per topic (different topics, different needs)"
kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe 2>/dev/null | grep -E "^Topic:" | awk '{print $2, $6, $8}' | column -t

banner "3. A partition replica = a directory on each broker that hosts it"
for b in 1 2 3; do
  echo "kafka-$b: $(docker compose exec -T kafka-$b ls /var/lib/kafka/data | grep -E '^orders-[0-9]+$' | sort -V | tr '\n' ' ')"
done
n1="$(docker compose exec -T kafka-1 ls /var/lib/kafka/data | grep -cE '^orders-[0-9]+$')"
expect "with RF=3 on 3 brokers every broker hosts all 6 orders partitions ($n1)" test "$n1" = 6

banner "4. Inside one partition directory: segment files"
docker compose exec -T kafka-1 ls -la /var/lib/kafka/data/orders-0
docker compose exec -T kafka-1 cat /var/lib/kafka/data/orders-0/partition.metadata; echo

banner "5. Records per partition (keys spread by murmur2(order_id) % 6)"
kcli stats -topic orders

banner "6. Dump the first records of the active segment (kafka-dump-log)"
seg="$(docker compose exec -T kafka-1 sh -c 'ls /var/lib/kafka/data/orders-0/*.log | head -1')"
kt kafka-dump-log --files "$seg" --print-data-log 2>/dev/null | head -8 | cut -c1-260 || true

banner "7. How many partitions does the cluster carry? (metadata + open files cost)"
curl -s localhost:7071/metrics | grep -E '^kafka_server_replicamanager_(partitioncount|leadercount)'
echo "open file handles of kafka-1 JVM: $(docker compose exec -T kafka-1 sh -c 'ls /proc/1/fd | wc -l')"
lab_done
