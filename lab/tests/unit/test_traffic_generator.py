import asyncio
import json
import os
import time
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError

from traffic_generator.config import Config
from traffic_generator.metrics import Metrics
from traffic_generator.worker import RequestFailed, Traffic, needed_virtual_users


def flow():
    return dict(flow_id=str(uuid4()), correlation_id=str(uuid4()), virtual_user=1)


@pytest.mark.parametrize("status,attempts", [(503, 3), (400, 1), (401, 1), (409, 1), (422, 1)])
async def test_retry_policy_does_not_blindly_retry_business_errors(status, attempts):
    requests = []

    def handle(request):
        requests.append(request)
        return httpx.Response(status, json={"error": {"code": "test"}})

    traffic = Traffic(Config(max_retries=2, backoff_ms=0), transport=httpx.MockTransport(handle))
    current = flow()
    try:
        with pytest.raises(RequestFailed):
            await traffic.request(current, "test", "inspection", "POST", "/inspections", headers={"Idempotency-Key": "stable"}, json={"a": 1})
        assert len(requests) == attempts
        assert {r.headers["Idempotency-Key"] for r in requests} == {"stable"}
        assert {r.headers["X-Correlation-ID"] for r in requests} == {current["correlation_id"]}
        assert len({r.headers["X-Request-ID"] for r in requests}) == attempts
    finally:
        await traffic.close()


async def test_connection_timeout_then_success_keeps_payload():
    requests = []

    def handle(request):
        requests.append(request)
        if len(requests) == 1:
            raise httpx.ReadTimeout("lost response", request=request)
        return httpx.Response(201, json={"id": "same"})

    traffic = Traffic(Config(max_retries=1, backoff_ms=0), transport=httpx.MockTransport(handle))
    try:
        result = await traffic.request(flow(), "test", "inspection", "POST", "/inspections", json={"x": 1})
        assert result.status_code == 201 and requests[0].content == requests[1].content
        assert traffic.metrics.counts["retries"] == 1
    finally:
        await traffic.close()


async def test_ambiguous_vehicle_create_reconciles_same_vin_via_rest():
    row = None
    posts = 0

    def handle(request):
        nonlocal row, posts
        if request.method == "POST":
            posts += 1
            body = json.loads(request.content)
            if row is None:
                row = dict(id=str(uuid4()), **body)
                raise httpx.ReadTimeout("commit succeeded, response lost", request=request)
            assert body["vin"] == row["vin"]
            return httpx.Response(409, json={"error": {"code": "constraint_conflict"}})
        assert request.url.params["vin"] == row["vin"]
        return httpx.Response(200, json=[row])

    traffic = Traffic(Config(max_retries=1, backoff_ms=0), transport=httpx.MockTransport(handle))
    try:
        result = await traffic.create_vehicle(flow())
        assert result == row and posts == 2
        assert traffic.metrics.counts["reconciled_vehicle_creates"] == 1
    finally:
        await traffic.close()


async def test_failed_flow_does_not_prevent_next_flow():
    traffic = Traffic(Config(max_retries=0), transport=httpx.MockTransport(lambda request: httpx.Response(503)))
    try:
        assert await traffic.lifecycle(1) is None
        assert await traffic.lifecycle(1) is None
        assert traffic.metrics.counts["flows_failed"] == 2
    finally:
        await traffic.close()


def test_metrics_are_bounded_and_distinguish_expected_errors():
    metrics = Metrics()
    for _ in range(10010):
        metrics.request(200, 10)
    metrics.request(404, 20, expected_error=True)
    snapshot = metrics.snapshot()
    assert snapshot["counts"]["total_requests"] == 10011
    assert snapshot["counts"]["failed_requests"] == snapshot["counts"]["expected_error_responses"] == 1
    assert snapshot["latency_window_samples"] == 10000 and snapshot["p95_latency_ms"] == 10


def test_configuration_ranges_and_concurrency_alias(monkeypatch):
    monkeypatch.delenv("VIRTUAL_USERS", raising=False)
    monkeypatch.setenv("TRAFFIC_CONCURRENCY", "7")
    assert Config().virtual_users == 7
    monkeypatch.setenv("VIRTUAL_USERS", "3")
    assert Config().virtual_users == 3
    with pytest.raises(ValidationError):
        Config(delete_rate=1.1)
    with pytest.raises(ValidationError):
        Config(replica_delays="500,0")
    with pytest.raises(ValidationError):
        Config(target_rps=-1)
    monkeypatch.setenv("TRAFFIC_TARGET_RPS", "12.5")
    assert Config().target_rps == 12.5


async def test_controlled_load_cap_stops_new_requests_but_keeps_worker_alive():
    import asyncio
    calls = []
    def handle(request):
        calls.append(request)
        return httpx.Response(201, json={"id": str(uuid4())})
    traffic = Traffic(Config(load_test_mode=True, load_test_max_vehicles=1), transport=httpx.MockTransport(handle))
    try:
        await traffic.load_create(1)
        blocked = asyncio.create_task(traffic.load_create(2))
        await asyncio.sleep(.01)
        assert len(calls) == 1 and not blocked.done()
        assert traffic.metrics.counts["load_creates"] == 1
        traffic.stop.set()
        await blocked
    finally:
        await traffic.close()


async def test_target_rps_paces_attempts_across_virtual_users():
    traffic = Traffic(Config(target_rps=50, max_retries=0), transport=httpx.MockTransport(lambda request: httpx.Response(200, json=[])))
    try:
        started = time.monotonic()
        await asyncio.gather(*(traffic.request(flow(), "test", "vehicle", "GET", "/vehicles") for _ in range(41)))
        # A fresh pacer may reclaim `burst` seconds of slots, then spaces the rest 20ms apart.
        assert time.monotonic() - started >= (40 - 50 * traffic.pacer.burst) / 50 * 0.9
        assert traffic.pacer.wait_seconds > 0
    finally:
        await traffic.close()


def test_pool_size_follows_unpaced_per_user_rate():
    # 150 attempts in 50 busy user-seconds: each user sustains 3 rps without pacing.
    assert needed_virtual_users(100, 150, 50, 30, 100) == 42
    assert needed_virtual_users(100, 150, 50, 5, 100) == 10  # At most 2x per step.
    assert needed_virtual_users(100, 150, 50, 30, 20) == 20  # TRAFFIC_MAX_VIRTUAL_USERS.
    # Oversized pool: users were busy for only 20 of their user-seconds.
    assert needed_virtual_users(10, 100, 20, 4, 100) == 3
    assert needed_virtual_users(10, 100, 20, 50, 100) == 25  # At most half per step.
    assert needed_virtual_users(10, 100, 0, 50, 100) == 25


async def test_runtime_control_resizes_pool_and_rejects_invalid_values(tmp_path):
    control = tmp_path / "control.json"
    config = Config(virtual_users=3, interval_ms=0, control_file=str(control), status_file=str(tmp_path / "status.json"))
    traffic = Traffic(config, transport=httpx.MockTransport(lambda request: httpx.Response(200)))
    release = asyncio.Event()

    async def lifecycle(number):
        await release.wait()

    def send(value, mtime_ns):
        control.write_text(json.dumps(value))
        os.utime(control, ns=(mtime_ns, mtime_ns))
        traffic.apply_control()
        traffic.adjust()

    traffic.lifecycle = lifecycle
    try:
        traffic.adjust()
        assert sorted(traffic.vus) == [1, 2, 3]
        send({"version": "v1", "virtual_users": 1}, 1)
        release.set()
        await asyncio.sleep(0.05)
        assert list(traffic.vus) == [1]  # Surplus users exit after their current flow.
        assert traffic.write_status("running")["control_version"] == "v1"
        for mtime_ns, value in enumerate([{"target_rps": -1}, {"virtual_users": 101}, ["not", "an", "object"]], start=2):
            send(value, mtime_ns)
            assert traffic.rate.model_dump() == dict(target_rps=0, virtual_users=1, interval_ms=0)
        send({"version": "v2", "target_rps": 20}, 9)
        assert traffic.pacer.rate == 20 and traffic.write_status("running")["target_rps"] == 20
    finally:
        traffic.stop.set()
        await asyncio.gather(*traffic.vus.values())
        await traffic.close()
