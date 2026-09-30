import json
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError

from traffic_generator.config import Config
from traffic_generator.metrics import Metrics
from traffic_generator.worker import RequestFailed, Traffic


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
