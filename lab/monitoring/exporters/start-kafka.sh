#!/bin/bash
set -euo pipefail
# Instrument only the broker JVM. Kafka CLI commands must not try to bind 9404.
export KAFKA_OPTS="${KAFKA_OPTS:-} -javaagent:/opt/metrics/jmx.jar=9404:/opt/metrics/jmx.yml"
exec /opt/kafka/bin/kafka-server-start-original.sh "$@"
