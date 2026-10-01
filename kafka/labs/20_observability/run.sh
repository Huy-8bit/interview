#!/usr/bin/env bash
# Lab 20 — observability tour: what Prometheus scrapes, key PromQL, Grafana dashboards, Kafka UI API.
source "$(dirname "$0")/../lib.sh"
q() { curl -s -G localhost:9090/api/v1/query --data-urlencode "query=$1" | python3 "$LAB_ROOT/scripts/internal/promfmt.py"; }

banner "1. Prometheus targets"
curl -s localhost:9090/api/v1/targets | python3 -c 'import sys,json; t=json.load(sys.stdin)["data"]["activeTargets"]; [print("   ", x["labels"]["job"].ljust(14), x["labels"]["instance"].ljust(26), x["health"]) for x in t if x["health"]=="up"]; print("    down (expected: scale-profile consumers not running):", sum(1 for x in t if x["health"]!="up"))'

banner "2. Key PromQL"
step "messages in /s per topic (broker)";        q 'sum by (topic) (rate(kafka_server_brokertopicmetrics_messagesin_total{topic!=""}[1m])) > 0'
step "bytes in/out per broker";                   q 'sum by (broker) (rate(kafka_server_brokertopicmetrics_bytesin_total{topic=""}[1m]))'
step "under-replicated / offline partitions";    q 'sum(kafka_server_replicamanager_underreplicatedpartitions)'; q 'max(kafka_controller_kafkacontroller_offlinepartitionscount)'
step "active controller";                         q 'kafka_controller_kafkacontroller_activecontrollercount == 1'
step "consumer lag per group";                    q 'sum by (group) (kafka_consumergroup_lag)'
step "app: produced/s, consumed/s";               q 'sum by (instance) (rate(produced_total[1m]))'; q 'sum by (group) (rate(consumed_total[1m]))'
step "app: processing p95 (s)";                   q 'histogram_quantile(0.95, sum by (le, group) (rate(processing_duration_seconds_bucket[5m])))'
step "broker Produce p99 total / remote time (ms)"; q 'max by (broker) (kafka_network_requestmetrics_total_time_ms{request="Produce",quantile="0.99"})'
step "broker CPU cores";                          q 'rate(process_cpu_seconds_total{job="kafka-broker"}[1m])'
step "alerts currently firing";                   curl -s localhost:9090/api/v1/alerts | python3 -c 'import sys,json; a=json.load(sys.stdin)["data"]["alerts"]; [print("   ", x["labels"]["alertname"], x["state"]) for x in a] or print("    none")'

banner "3. Grafana dashboards (provisioned from monitoring/grafana/dashboards)"
n="$(curl -s 'localhost:3000/api/search?tag=kafka-lab' | python3 -c 'import sys,json; d=json.load(sys.stdin); [print("   ", x["title"], "-> http://localhost:3000" + x["url"]) for x in d]; print(len(d))' | tee /dev/stderr | tail -1)"
expect "6 dashboards provisioned ($n)" test "$n" = 6
python3 scripts/internal/check_dashboards.py | tail -1

banner "4. Kafka UI (http://localhost:8080) API"
curl -s localhost:8080/api/clusters | python3 -c 'import sys,json; [print("    cluster", c["name"], "status", c["status"], "brokers", c["brokerCount"], "online partitions", c["onlinePartitionCount"]) for c in json.load(sys.stdin)]'
expect "Kafka UI sees the cluster online" bash -c "curl -s localhost:8080/api/clusters | grep -qi '\"status\":\"online\"'"
lab_done
