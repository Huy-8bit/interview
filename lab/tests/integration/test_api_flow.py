import asyncio
from uuid import uuid4

import pytest

from scripts.lab_client import poll

pytestmark = pytest.mark.integration


async def test_vehicle_api_validation_cache_and_outbox(client, db, redis_client):
    vehicle = await client.vehicle()
    payload = {
        k: vehicle[k] for k in ["vin", "model", "manufacturer", "production_year", "owner_name"]
    }
    duplicate = await client.request("vehicle", "POST", "/vehicles", json=payload)
    assert duplicate.status_code == 409
    invalid = await client.request("vehicle", "POST", "/vehicles", json={**payload, "vin": "bad"})
    assert invalid.status_code == 422
    path = f"/vehicles/{vehicle['id']}"
    first = await client.request("vehicle", "GET", path)
    second = await client.request("vehicle", "GET", path)
    assert first.headers["x-cache"] == "MISS" and second.headers["x-cache"] == "HIT"
    assert await redis_client.ttl(f"vehicle:{vehicle['id']}") > 0
    patched = await client.json("vehicle", "PATCH", path, json={"owner_name": "Updated owner"})
    assert patched["owner_name"] == "Updated owner"
    refreshed = await client.request("vehicle", "GET", path)
    assert (
        refreshed.headers["x-cache"] == "MISS" and refreshed.json()["owner_name"] == "Updated owner"
    )
    rows = await db(
        "vehicle", "SELECT event_type FROM outbox_events WHERE aggregate_id = :id", id=vehicle["id"]
    )
    assert {r["event_type"] for r in rows} == {"vehicle.created", "vehicle.updated"}


async def test_end_to_end_fail_warranty_repair_notification_and_pass(client, db):
    vehicle = await client.vehicle()
    coverage = await client.warranty(vehicle["id"])
    assert coverage["covered"] is True
    key = str(uuid4())
    inspection = await client.inspection(vehicle["id"], key=key)
    assert await client.inspection(vehicle["id"], key=key) == inspection
    conflict = await client.request(
        "inspection",
        "POST",
        "/inspections",
        headers={"Idempotency-Key": key},
        json={"vehicle_id": vehicle["id"], "notes": "different"},
    )
    assert conflict.status_code == 409
    no_key = await client.request(
        "inspection", "POST", "/inspections", json={"vehicle_id": vehicle["id"]}
    )
    assert no_key.status_code == 422
    invalid_fail = await client.request(
        "inspection", "POST", f"/inspections/{inspection['id']}/complete", json={"result": "FAIL"}
    )
    assert invalid_fail.status_code == 422
    await client.complete(inspection["id"], "FAIL")
    repair = await client.repair(inspection["id"])
    assert repair["warranty_covered"] is True and repair["status"] == "OPEN"
    notifications = await client.json("repair", "GET", f"/repairs/{repair['id']}/notifications")
    assert len(notifications) == 1 and notifications[0]["status"] == "SIMULATED"
    await client.json("repair", "PATCH", f"/repairs/{repair['id']}", json={"status": "IN_PROGRESS"})
    finished = await client.json(
        "repair", "PATCH", f"/repairs/{repair['id']}", json={"status": "COMPLETED"}
    )
    assert finished["status"] == "COMPLETED"
    invalid = await client.request(
        "repair", "PATCH", f"/repairs/{repair['id']}", json={"status": "IN_PROGRESS"}
    )
    assert invalid.status_code == 409
    passed = await client.inspection(vehicle["id"])
    await client.complete(passed["id"], "PASS")

    async def published_pass():
        return await db(
            "inspection",
            "SELECT id FROM outbox_events WHERE payload->'data'->>'inspection_id' = :id AND event_type = 'inspection.passed' AND status = 'PUBLISHED'",
            id=passed["id"],
        )

    await poll(published_pass)
    assert await client.repairs(passed["id"]) == []
    repair_events = await db(
        "repair", "SELECT id FROM outbox_events WHERE payload->'data'->>'id' = :id", id=repair["id"]
    )
    assert len(repair_events) == 1


async def test_expired_warranty_produces_uncovered_repair(client):
    vehicle = await client.vehicle()
    coverage = await client.warranty(vehicle["id"])
    await client.json("warranty", "POST", f"/warranties/{coverage['warranty_id']}/expire")
    inspection = await client.inspection(vehicle["id"])
    await client.complete(inspection["id"], "FAIL")
    assert (await client.repair(inspection["id"]))["warranty_covered"] is False


async def test_concurrent_api_retries_and_redis_result_eviction(client, redis_client):
    vehicle = await client.vehicle()
    await client.inspection(vehicle["id"])  # Wait until the projection is ready.
    key = str(uuid4())
    values = await asyncio.gather(*(client.inspection(vehicle["id"], key=key) for _ in range(8)))
    assert len({v["id"] for v in values}) == 1
    import hashlib

    digest = hashlib.sha256(key.encode()).hexdigest()
    await redis_client.delete(f"idem:inspection-service:POST:/inspections:{digest}")
    assert await client.inspection(vehicle["id"], key=key) == values[0]


async def test_repair_api_idempotency(client):
    vehicle = await client.vehicle()
    await client.warranty(vehicle["id"])
    inspection = await client.inspection(vehicle["id"])
    key = str(uuid4())
    body = {
        "vehicle_id": vehicle["id"],
        "inspection_id": inspection["id"],
        "description": "Manual workshop request",
    }
    first = await client.json(
        "repair", "POST", "/repairs", headers={"Idempotency-Key": key}, json=body
    )
    retry = await client.json(
        "repair", "POST", "/repairs", headers={"Idempotency-Key": key}, json=body
    )
    assert first == retry
    conflict = await client.request(
        "repair",
        "POST",
        "/repairs",
        headers={"Idempotency-Key": key},
        json={**body, "description": "Different"},
    )
    assert conflict.status_code == 409
