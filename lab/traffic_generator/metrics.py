import json
import math
import time
from collections import Counter, deque
from datetime import UTC, datetime


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
        self.latencies = deque(maxlen=10000)
        self.latency_sum = 0.0

    def request(self, status, latency, expected_error=False):
        self.counts["total_requests"] += 1
        self.counts["successful_requests" if status is not None and 200 <= status < 300 else "failed_requests"] += 1
        if expected_error:
            self.counts["expected_error_responses"] += 1
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
