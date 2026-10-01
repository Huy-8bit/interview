#!/usr/bin/env python3
"""Generates the provisioned Grafana dashboards (monitoring/grafana/dashboards/*.json).

Dashboards are code: edit the panel lists below and run
    python3 monitoring/grafana/dashgen.py
Grafana reloads the files within 30s (no restart needed).
"""
import json
import os

DS = {"type": "prometheus", "uid": "prometheus"}
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dashboards")


class Board:
    def __init__(self, uid, title, description, variables=None):
        self.uid, self.title, self.description = uid, title, description
        self.panels, self.x, self.y, self.row_h, self.next_id = [], 0, 0, 0, 1
        self.variables = variables or []

    def _place(self, w, h):
        if self.x + w > 24:
            self.x, self.y = 0, self.y + self.row_h
            self.row_h = 0
        pos = {"x": self.x, "y": self.y, "w": w, "h": h}
        self.x += w
        self.row_h = max(self.row_h, h)
        return pos

    def row(self, title):
        if self.x:
            self.x, self.y, self.row_h = 0, self.y + self.row_h, 0
        self.panels.append({"type": "row", "title": title, "id": self.next_id, "collapsed": False,
                            "gridPos": {"x": 0, "y": self.y, "w": 24, "h": 1}, "panels": []})
        self.next_id += 1
        self.y += 1

    def _targets(self, exprs):
        out = []
        for i, e in enumerate(exprs):
            expr, legend = e if isinstance(e, tuple) else (e, "")
            out.append({"refId": chr(65 + i), "datasource": DS, "expr": expr, "legendFormat": legend})
        return out

    def ts(self, title, exprs, unit="short", w=12, h=8, desc="", stack=False, thresholds=None):
        p = {"type": "timeseries", "title": title, "description": desc, "datasource": DS, "id": self.next_id,
             "gridPos": self._place(w, h), "targets": self._targets(exprs),
             "fieldConfig": {"defaults": {"unit": unit, "custom": {"lineWidth": 1, "fillOpacity": 10,
                                                                   "showPoints": "never",
                                                                   "stacking": {"mode": "normal" if stack else "none"}}},
                             "overrides": []},
             "options": {"legend": {"displayMode": "table", "placement": "right", "calcs": ["lastNotNull", "max"]},
                         "tooltip": {"mode": "multi", "sort": "desc"}}}
        if thresholds:
            p["fieldConfig"]["defaults"]["thresholds"] = thresholds
            p["fieldConfig"]["defaults"]["custom"]["thresholdsStyle"] = {"mode": "line"}
        self.panels.append(p)
        self.next_id += 1

    def stat(self, title, expr, unit="short", w=4, h=4, desc="", steps=None, legend=""):
        steps = steps or [{"color": "green", "value": None}]
        self.panels.append({"type": "stat", "title": title, "description": desc, "datasource": DS, "id": self.next_id,
                            "gridPos": self._place(w, h), "targets": self._targets([(expr, legend)]),
                            "fieldConfig": {"defaults": {"unit": unit, "thresholds": {"mode": "absolute", "steps": steps}},
                                            "overrides": []},
                            "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background",
                                        "graphMode": "none", "textMode": "value_and_name" if legend else "value"}})
        self.next_id += 1

    def table(self, title, expr, w=12, h=8, desc="", rename=None, exclude=()):
        excl = {k: True for k in ("Time", "__name__", "job", "instance", "Value") + tuple(exclude)}
        self.panels.append({"type": "table", "title": title, "description": desc, "datasource": DS, "id": self.next_id,
                            "gridPos": self._place(w, h),
                            "targets": [{"refId": "A", "datasource": DS, "expr": expr, "format": "table", "instant": True}],
                            "transformations": [{"id": "organize", "options": {"excludeByName": excl,
                                                                               "renameByName": rename or {}}}],
                            "options": {"showHeader": True}, "fieldConfig": {"defaults": {}, "overrides": []}})
        self.next_id += 1

    def text(self, content, w=24, h=3):
        self.panels.append({"type": "text", "title": "", "id": self.next_id, "gridPos": self._place(w, h),
                            "options": {"mode": "markdown", "content": content}})
        self.next_id += 1

    def save(self):
        tmpl = []
        for v in self.variables:
            tmpl.append({"name": v["name"], "label": v.get("label", v["name"]), "type": "query", "datasource": DS,
                         "query": {"query": v["query"], "refId": "v"}, "definition": v["query"], "refresh": 2,
                         "includeAll": v.get("all", False), "multi": v.get("multi", False),
                         "current": {}, "sort": 1})
        board = {"uid": self.uid, "title": self.title, "description": self.description, "tags": ["kafka-lab"],
                 "timezone": "browser", "schemaVersion": 39, "version": 1, "refresh": "5s",
                 "time": {"from": "now-15m", "to": "now"}, "editable": True,
                 "templating": {"list": tmpl}, "panels": self.panels,
                 "links": [{"title": "Kafka Lab", "type": "dashboards", "tags": ["kafka-lab"], "asDropdown": True}]}
        path = os.path.join(OUT, self.uid + ".json")
        with open(path, "w") as f:
            json.dump(board, f, indent=1)
        print("wrote", path, len(self.panels), "panels")


RED1 = [{"color": "green", "value": None}, {"color": "red", "value": 1}]
BROKERS = [{"color": "red", "value": None}, {"color": "orange", "value": 2}, {"color": "green", "value": 3}]
CTRL = [{"color": "red", "value": None}, {"color": "green", "value": 1}, {"color": "red", "value": 2}]

# --------------------------------------------------------------------------- 1. overview
b = Board("kafka-cluster-overview", "Kafka Cluster Overview",
          "Health at a glance: brokers, controller, partition health, throughput, consumer lag.")
b.stat("Brokers up (scraped)", 'count(up{job="kafka-broker"} == 1)', steps=BROKERS)
b.stat("Active controllers", "sum(kafka_controller_kafkacontroller_activecontrollercount)", steps=CTRL,
       desc="KRaft: exactly one node must report 1. 0 = no quorum leader, >1 = split brain (should never happen).")
b.stat("Controller node", "kafka_controller_kafkacontroller_activecontrollercount == 1",
       legend="{{broker}}", desc="Which node is the KRaft quorum leader (active controller).")
b.stat("Under-replicated partitions", "sum(kafka_server_replicamanager_underreplicatedpartitions)", steps=RED1,
       desc="Partitions whose ISR is smaller than the replica set, counted by their leaders.")
b.stat("Offline partitions", "max(kafka_controller_kafkacontroller_offlinepartitionscount)", steps=RED1,
       desc="Partitions with NO leader -> reads and writes fail.")
b.stat("Under min ISR", "sum(kafka_server_replicamanager_underminisrpartitioncount)", steps=RED1,
       desc="ISR < min.insync.replicas -> producers with acks=all get NOT_ENOUGH_REPLICAS.")
b.stat("Topics", "max(kafka_controller_kafkacontroller_globaltopiccount)", w=4)
b.stat("Partitions (leaders)", "max(kafka_controller_kafkacontroller_globalpartitioncount)", w=4)
b.stat("Messages in /s", "sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=\"\"}[1m]))", unit="short", w=4)
b.stat("Bytes in /s", "sum(rate(kafka_server_brokertopicmetrics_bytesin_total{topic=\"\"}[1m]))", unit="Bps", w=4)
b.stat("Bytes out /s", "sum(rate(kafka_server_brokertopicmetrics_bytesout_total{topic=\"\"}[1m]))", unit="Bps", w=4)
b.stat("Total consumer lag", "sum(kafka_consumergroup_lag)", w=4,
       steps=[{"color": "green", "value": None}, {"color": "orange", "value": 1000}, {"color": "red", "value": 10000}])
b.row("Throughput")
b.ts("Messages in /s by topic", [('sum by (topic) (rate(kafka_server_brokertopicmetrics_messagesin_total{topic!=""}[1m]))', "{{topic}}")])
b.ts("Bytes in / out by broker", [('sum by (broker) (rate(kafka_server_brokertopicmetrics_bytesin_total{topic=""}[1m]))', "in {{broker}}"),
                                   ('-sum by (broker) (rate(kafka_server_brokertopicmetrics_bytesout_total{topic=""}[1m]))', "out {{broker}}")],
     unit="Bps", desc="out is drawn negative. Includes consumer fetches, NOT replication (see Broker Health).")
b.row("Consumers")
b.ts("Consumer lag by group", [("sum by (group) (kafka_consumergroup_lag)", "{{group}}")],
     desc="lag = log end offset (high watermark) - committed offset. Computed by lag-exporter via the Admin API.")
b.ts("Leaders per broker", [("sum by (broker) (kafka_server_replicamanager_leadercount)", "{{broker}}")],
     desc="Leader balance: after a broker restart leaders move back once auto.leader.rebalance runs (every 30s here).")
b.save()

# --------------------------------------------------------------------------- 2. producer
b = Board("producer-performance", "Producer Performance",
          "Application-side producer metrics (Go services) + broker-side Produce request timings.")
b.ts("Records acknowledged /s (produced_total)", [("sum by (job, instance, topic) (rate(produced_total[1m]))", "{{instance}} -> {{topic}}")])
b.ts("Produce errors /s", [("sum by (instance, topic, error) (rate(produce_error_total[1m]))", "{{instance}} {{topic}} {{error}}")],
     desc="Errors AFTER the client exhausted its retries / delivery timeout (e.g. NOT_ENOUGH_REPLICAS, timeouts).")
b.ts("Produce latency (client, Produce() -> ack)", [
    ("histogram_quantile(0.50, sum by (le, instance) (rate(produce_latency_seconds_bucket[1m])))", "p50 {{instance}}"),
    ("histogram_quantile(0.99, sum by (le, instance) (rate(produce_latency_seconds_bucket[1m])))", "p99 {{instance}}")],
    unit="s", desc="Includes linger + batching + network + broker append + (acks=all) replication wait.")
b.ts("Broker Produce request time p99 by broker", [
    ('max by (broker) (kafka_network_requestmetrics_total_time_ms{request="Produce",quantile="0.99"})', "total {{broker}}"),
    ('max by (broker) (kafka_network_requestmetrics_remote_time_ms{request="Produce",quantile="0.99"})', "remote (waiting ISR) {{broker}}")],
    unit="ms", desc="remote time = time the leader waited for followers to replicate (acks=all). ~0 for acks=1/0.")
b.ts("Produce requests /s by broker", [('sum by (broker) (rate(kafka_network_requestmetrics_requests_total{request="Produce"}[1m]))', "{{broker}}")],
     desc="Fewer requests for the same record rate = bigger batches (linger / batch.size working).")
b.ts("Failed produce requests /s", [('sum by (broker) (rate(kafka_server_brokertopicmetrics_failedproducerequests_total{topic=""}[1m]))', "{{broker}}")])
b.ts("Bytes in by topic", [('sum by (topic) (rate(kafka_server_brokertopicmetrics_bytesin_total{topic!=""}[1m]))', "{{topic}}")], unit="Bps")
b.ts("Records per produce request (approx)", [
    ('sum(rate(kafka_server_brokertopicmetrics_messagesin_total{topic=""}[1m])) / sum(rate(kafka_network_requestmetrics_requests_total{request="Produce"}[1m]))', "records/request")],
    desc="Rough batching efficiency indicator across the cluster.")
b.save()

# --------------------------------------------------------------------------- 3. consumer
b = Board("consumer-performance", "Consumer Performance",
          "Records/s, processing time, retries, DLQ, duplicates and rebalances per consumer instance.")
b.ts("Records processed /s by instance", [("sum by (instance, group) (rate(consumed_total[1m]))", "{{instance}} ({{group}})")])
b.ts("Records processed /s by partition (order-processing-group)", [
    ('sum by (partition, instance) (rate(consumed_total{group="order-processing-group"}[1m]))', "P{{partition}} @ {{instance}}")],
    desc="Shows which instance owns which partition and hot partitions.")
b.ts("Processing duration p95", [("histogram_quantile(0.95, sum by (le, instance) (rate(processing_duration_seconds_bucket[1m])))", "{{instance}}")], unit="s")
b.ts("End-to-end latency p95 (record timestamp -> processed)", [
    ("histogram_quantile(0.95, sum by (le, group) (rate(end_to_end_latency_seconds_bucket[1m])))", "{{group}}")], unit="s",
    desc="Grows with consumer lag: a record waits in the log until the consumer reaches it.")
b.ts("Errors / retries / DLQ /s", [("sum by (group) (rate(consume_error_total[1m]))", "errors {{group}}"),
                                   ("sum by (group) (rate(retry_total[1m]))", "retry {{group}}"),
                                   ("sum by (group) (rate(dlq_total[1m]))", "DLQ {{group}}")])
b.ts("Duplicates skipped (idempotent consumer)", [("sum by (instance, group) (increase(duplicate_skipped_total[5m]))", "{{instance}}")])
b.ts("Rebalance callbacks", [("sum by (instance, group, event) (increase(rebalance_events_total[5m]))", "{{instance}} {{event}}")],
     desc="assigned / revoked / lost per 5m. lost = session timeout / fenced.")
b.ts("Assigned partitions per instance", [("sum by (instance, group, topic) (assigned_partitions)", "{{instance}} {{topic}}")], stack=True)
b.ts("Offset commits /s", [("sum by (instance, result) (rate(offset_commit_total[1m]))", "{{instance}} {{result}}")])
b.ts("Broker FetchConsumer time p99", [('max by (broker) (kafka_network_requestmetrics_total_time_ms{request="FetchConsumer",quantile="0.99"})', "{{broker}}")],
     unit="ms", desc="Includes fetch.max.wait when there is no new data (long polling) — high values on idle topics are normal.")
b.save()

# --------------------------------------------------------------------------- 4. lag
b = Board("consumer-lag", "Consumer Lag",
          "Committed offset vs log end offset per group / partition (lag-exporter, Admin API).",
          variables=[{"name": "group", "query": "label_values(kafka_consumergroup_lag, group)"}])
b.ts("Total lag by group", [("sum by (group) (kafka_consumergroup_lag)", "{{group}}")], w=24)
b.ts("Lag per partition — $group", [('sum by (topic, partition) (kafka_consumergroup_lag{group="$group"})', "{{topic}} P{{partition}}")])
b.ts("Lag growth rate — $group (records/s, >0 = falling behind)", [
    ('sum by (topic) (deriv(kafka_consumergroup_lag{group="$group"}[1m]))', "{{topic}}")])
b.ts("Log end offset vs committed — $group", [
    ('sum by (topic) (kafka_topic_partition_current_offset and on(topic, partition) kafka_consumergroup_lag{group="$group"})', "log end {{topic}}"),
    ('sum by (topic) (kafka_consumergroup_committed_offset{group="$group"})', "committed {{topic}}")])
b.ts("Members per group", [("kafka_consumergroup_members", "{{group}}")])
b.table("Partition owners — $group", 'kafka_consumergroup_partition_owner{group="$group"}', w=12, h=10,
        rename={"member": "member (client.id)"})
b.table("Lag per partition — $group (now)", 'kafka_consumergroup_lag{group="$group"}', w=12, h=10, exclude=())
b.save()

# --------------------------------------------------------------------------- 5. broker health
b = Board("broker-health", "Broker Health", "Per broker CPU, memory, GC, thread pools, request rates and disk.")
b.ts("CPU (cores) by broker", [("rate(process_cpu_seconds_total{job=\"kafka-broker\"}[1m])", "{{broker}}")], unit="short")
b.ts("JVM heap used by broker", [('jvm_memory_used_bytes{job="kafka-broker",area="heap"}', "{{broker}}")], unit="bytes")
b.ts("GC time per second", [('sum by (broker) (rate(jvm_gc_collection_seconds_sum{job="kafka-broker"}[1m]))', "{{broker}}")], unit="s",
     desc="Seconds spent in GC per second. Long pauses -> ISR shrink, session timeouts, quorum re-election.")
b.ts("Resident memory (RSS)", [('process_resident_memory_bytes{job="kafka-broker"}', "{{broker}}")], unit="bytes")
b.ts("Request handler idle ratio (1 = idle)", [("kafka_server_kafkarequesthandlerpool_requesthandler_avg_idle_ratio", "{{broker}}")],
     unit="percentunit", desc="< 0.3 sustained = I/O threads saturated (num.io.threads).")
b.ts("Network processor idle ratio", [("kafka_network_socketserver_networkprocessoravgidlepercent", "{{broker}}")], unit="percentunit")
b.ts("Requests /s by type", [('sum by (request) (rate(kafka_network_requestmetrics_requests_total{request=~"Produce|Fetch|FetchConsumer|OffsetCommit|Heartbeat|JoinGroup|SyncGroup|Metadata|ConsumerGroupHeartbeat"}[1m]))', "{{request}}")])
b.ts("Request queue size", [("kafka_network_requestchannel_requestqueuesize", "{{broker}}")], desc="Requests waiting for an I/O thread.")
b.ts("Replication bytes in / out", [('sum by (broker) (rate(kafka_server_brokertopicmetrics_replicationbytesin_total{topic=""}[1m]))', "repl in {{broker}}"),
                                     ('sum by (broker) (rate(kafka_server_brokertopicmetrics_replicationbytesout_total{topic=""}[1m]))', "repl out {{broker}}")], unit="Bps",
     desc="Follower fetch traffic. With RF=3 every produced byte is copied twice.")
b.ts("Log size on disk by broker", [("sum by (broker) (kafka_log_log_size)", "{{broker}}")], unit="bytes")
b.ts("Fetch / Produce p99 total time", [('max by (broker, request) (kafka_network_requestmetrics_total_time_ms{request=~"Produce|Fetch",quantile="0.99"})', "{{request}} {{broker}}")], unit="ms",
     desc="Fetch = follower replication fetches (long-poll, replica.fetch.wait.max.ms=500).")
b.ts("Log size by topic", [('sum by (topic) (kafka_log_log_size{topic!~"__.*"})', "{{topic}}")], unit="bytes")
b.save()

# --------------------------------------------------------------------------- 6. partitions
b = Board("partition-replication-health", "Partition / Replication Health",
          "ISR, under-replicated / offline partitions, leader distribution and elections.",
          variables=[{"name": "topic", "query": "label_values(kafka_topic_partition_leader, topic)"}])
b.stat("Under-replicated", "sum(kafka_server_replicamanager_underreplicatedpartitions)", steps=RED1, w=4)
b.stat("Under min ISR", "sum(kafka_server_replicamanager_underminisrpartitioncount)", steps=RED1, w=4)
b.stat("At min ISR", "sum(kafka_server_replicamanager_atminisrpartitioncount)", w=4,
       steps=[{"color": "green", "value": None}, {"color": "orange", "value": 1}],
       desc="ISR == min.insync.replicas: one more failure and acks=all writes stop.")
b.stat("Offline partitions", "max(kafka_controller_kafkacontroller_offlinepartitionscount)", steps=RED1, w=4)
b.stat("Fenced brokers", "max(kafka_controller_kafkacontroller_fencedbrokercount)", steps=RED1, w=4,
       desc="Brokers the KRaft controller fenced (missed heartbeats for broker.session.timeout.ms).")
b.stat("Preferred leader imbalance", "max(kafka_controller_kafkacontroller_preferredreplicaimbalancecount)", w=4,
       steps=[{"color": "green", "value": None}, {"color": "orange", "value": 1}])
b.ts("ISR shrinks / expands per minute", [("sum by (broker) (increase(kafka_server_replicamanager_isrshrinks_total[1m]))", "shrink {{broker}}"),
                                          ("sum by (broker) (increase(kafka_server_replicamanager_isrexpands_total[1m]))", "expand {{broker}}")],
     desc="Shrink: a follower fell behind replica.lag.time.max.ms (10s here) or died. Expand: it caught up again.")
b.ts("Under-replicated partitions by broker (leader side)", [("kafka_server_replicamanager_underreplicatedpartitions", "{{broker}}")])
b.ts("Leader count by broker", [("kafka_server_replicamanager_leadercount", "{{broker}}")])
b.ts("Replica fetcher max lag (records)", [("kafka_server_replicafetchermanager_maxlag{clientid=\"Replica\"}", "{{broker}}")],
     desc="How far this broker's followers are behind their leaders.")
b.ts("ISR size per partition — $topic", [('kafka_topic_partition_in_sync_replicas{topic="$topic"}', "P{{partition}}")])
b.ts("Leader (broker id) per partition — $topic", [('kafka_topic_partition_leader{topic="$topic"}', "P{{partition}}")],
     desc="Step changes = leader election (broker failure, preferred leader rebalance).")
b.ts("Leader elections (cumulative)", [("max(kafka_controller_controllerstats_electionfromeligibleleaderreplicas_total)", "clean elections (from ISR/ELR)"),
                                       ("max(kafka_controller_controllerstats_uncleanleaderelections_total)", "UNCLEAN elections")])
b.table("Partitions not fully in sync", "kafka_topic_partition_under_replicated == 1", w=12, h=8)
b.save()
