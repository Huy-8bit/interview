#!/bin/bash
set -euo pipefail
for domain in vehicle warranty inspection repair; do
  for suffix in events events-dlq; do
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 \
      --create --if-not-exists --topic "${domain}-${suffix}" \
      --partitions "${KAFKA_TOPIC_PARTITIONS:-3}" --replication-factor 1 \
      --config retention.ms=604800000 --config min.insync.replicas=1
  done
done
