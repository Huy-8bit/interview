#!/bin/bash
set -euo pipefail
bootstrap="${KAFKA_BOOTSTRAP_SERVERS:-kafka-1:9092,kafka-2:9092,kafka-3:9092}"
partitions="${KAFKA_TOPIC_PARTITIONS:-3}"
if (( partitions < 3 )); then echo 'KAFKA_TOPIC_PARTITIONS must be >= 3' >&2; exit 1; fi
for domain in vehicle warranty inspection repair; do
  for suffix in events events-dlq; do
    topic="${domain}-${suffix}"
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$bootstrap" \
      --create --if-not-exists --topic "$topic" \
      --partitions "$partitions" --replication-factor 3 \
      --config retention.ms=604800000 --config min.insync.replicas=2
    description=$(/opt/kafka/bin/kafka-topics.sh --bootstrap-server "$bootstrap" --describe --topic "$topic")
    echo "$description"
    # Refuse a silently reused RF=1 topic. Reassignment is a deliberate admin operation.
    echo "$description" | awk -v expected="$partitions" '
      /PartitionCount:/ {for(i=1;i<=NF;i++) {if($i=="ReplicationFactor:" && $(i+1)!=3) exit 1; if($i=="PartitionCount:" && $(i+1)<expected) exit 1}}
      /Partition:/ {for(i=1;i<=NF;i++) if($i=="Replicas:" && split($(i+1),r,",")!=3) exit 1}
    '
    /opt/kafka/bin/kafka-configs.sh --bootstrap-server "$bootstrap" \
      --entity-type topics --entity-name "$topic" --alter --add-config min.insync.replicas=2
  done
done

# Connect's config topic must have exactly ONE partition; offset/status can have more.
# CDC row streams and heartbeat topics are separate from business events.
create_cdc_topic() {
  local name="$1" count="$2" policy="$3"
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$bootstrap" --create --if-not-exists \
    --topic "$name" --partitions "$count" --replication-factor 3 \
    --config min.insync.replicas=2 --config cleanup.policy="$policy"
  local description
  description=$(/opt/kafka/bin/kafka-topics.sh --bootstrap-server "$bootstrap" --describe --topic "$name")
  echo "$description"
  echo "$description" | awk -v count="$count" '
    /PartitionCount:/ {for(i=1;i<=NF;i++) {if($i=="ReplicationFactor:" && $(i+1)!=3) exit 1; if($i=="PartitionCount:" && $(i+1)!=count) exit 1}}'
  /opt/kafka/bin/kafka-configs.sh --bootstrap-server "$bootstrap" --entity-type topics \
    --entity-name "$name" --alter --add-config "min.insync.replicas=2,cleanup.policy=$policy"
}
create_cdc_topic connect-configs 1 compact
create_cdc_topic connect-offsets 3 compact
create_cdc_topic connect-status 3 compact
for entry in vehicle:vehicles warranty:warranties inspection:inspections repair:repair_requests; do
  domain=${entry%%:*}
  table=${entry#*:}
  create_cdc_topic "$domain-cdc.public.$table" 3 delete
  create_cdc_topic "__debezium-heartbeat.$domain-cdc" 1 compact
done
