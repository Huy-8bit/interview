import json
import math
import time
from collections import Counter, deque
from datetime import UTC, datetime

from prometheus_client import CollectorRegistry, Histogram, start_http_server
from prometheus_client.core import CounterMetricFamily


class TrafficCounters:
    mapping = {
        "traffic_requests_total": "total_requests", "traffic_requests_failed_total": "failed_requests",
        "traffic_flow_completed_total": "flows_completed", "traffic_flow_failed_total": "flows_failed",
        "traffic_flows_started_total": "flows_started", "traffic_retries_total": "retries",
        "vehicles_created_total": "created_vehicles", "inspections_created_total": "created_inspections",
        "repairs_created_total": "created_repairs", "traffic_load_creates_total": "load_creates",
    }
    def __init__(self, counts):
        self.counts = counts

    def collect(self):
        for name, key in self.mapping.items():
            metric = CounterMetricFamily(name, name.replace("_", " "), labels=["service"])
            metric.add_metric(["traffic-generator"], self.counts[key])
            yield metric



def emit(action, *, flow=None, **fields):
    record = dict(timestamp=datetime.now(UTC).isoformat(), service="traffic-generator", action=action)
    if flow:
        record.update(flow)
    record.update(fields)
    print(json.dumps(record, ensure_ascii=False, default=str), flush=True)


class Metrics:
    def __init__(self):
        self.started = time.monotonic()
        self.counts = Counter()
        self.registry = CollectorRegistry()
        self.registry.register(TrafficCounters(self.counts))
        self.duration = Histogram("traffic_request_duration_seconds", "All REST attempt latencies", ["service"],
                                  buckets=(.005,.01,.025,.05,.1,.25,.5,1,2.5,5,10,30), registry=self.registry).labels("traffic-generator")
        self.server = None
        self.latencies = deque(maxlen=10000)
        self.latency_sum = 0.0

    def request(self, status, latency, expected_error=False):
        self.counts["total_requests"] += 1
        self.counts["successful_requests" if status is not None and 200 <= status < 300 else "failed_requests"] += 1
        if expected_error:
            self.counts["expected_error_responses"] += 1
        self.duration.observe(latency / 1000)
        self.latencies.append(latency)
        self.latency_sum += latency

    def snapshot(self):
        ordered = sorted(self.latencies)
        total = self.counts["total_requests"]
        return dict(
            counts=dict(self.counts), elapsed_seconds=round(time.monotonic() - self.started, 2),
            avg_latency_ms=round(self.latency_sum / total, 2) if total else 0,
            p95_latency_ms=round(ordered[math.ceil(0.95 * len(ordered)) - 1], 2) if ordered else 0,
            latency_window_samples=len(ordered), latency_window_limit=10000,
        )

    def start_server(self, port):
        self.server, self.server_thread = start_http_server(port, registry=self.registry)

    def close_server(self):
        if self.server:
            self.server.shutdown()
            self.server.server_close()
