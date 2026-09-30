"""Opt-in real process crash, HTTP timeout, pool exhaustion and stale-cache drills."""

import asyncio
import json
import os
from uuid import uuid4

import httpx
from redis.asyncio import Redis
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from lab_client import LabClient, poll


async def main():
    client = LabClient()
    engines = {
        s: create_async_engine(os.environ[s.upper() + "_DATABASE_URL"])
        for s in ("vehicle", "repair")
    }
    redis = Redis.from_url(os.environ["REDIS_URL"], decode_responses=True)

    async def query(service, sql, **params):
        async with engines[service].connect() as connection:
            return (await connection.execute(text(sql), params)).mappings().all()

    async def fault(service, name, **body):
        response = await client.request(service, "POST", "/lab/" + name, json=body)
        if response.status_code == 404:
            raise SystemExit("Enable fault endpoints first: make chaos-up")
        response.raise_for_status()

    try:
        await fault("vehicle", "outbox-failures", count=2)
        vehicle = await client.vehicle()

        async def attempted():
            rows = await query(
                "vehicle",
                "SELECT status, attempts FROM outbox_events WHERE aggregate_id=:id",
                id=vehicle["id"],
            )
            return rows and rows[0]["attempts"] >= 1

        await poll(attempted)
        await client.warranty(vehicle["id"])
        print("PASS: outbox survives injected failures and reaches Kafka", flush=True)

        original = await client.json("vehicle", "GET", f"/vehicles/{vehicle['id']}")
        stale = {**original, "owner_name": "STALE (injected for two seconds)"}
        await redis.set(f"vehicle:{vehicle['id']}", json.dumps(stale), ex=2)
        assert (await client.json("vehicle", "GET", f"/vehicles/{vehicle['id']}"))[
            "owner_name"
        ] == stale["owner_name"]

        async def fresh():
            row = await client.json("vehicle", "GET", f"/vehicles/{vehicle['id']}")
            return row["owner_name"] == original["owner_name"]

        await poll(fresh)
        print("PASS: deliberately stale cache heals after TTL", flush=True)

        inspection = await client.inspection(vehicle["id"])
        body = {
            "vehicle_id": vehicle["id"],
            "inspection_id": inspection["id"],
            "description": "HTTP timeout drill",
        }
        await fault("warranty", "http-delay", seconds=3)
        try:
            response = await client.request(
                "repair", "POST", "/repairs", json=body, headers={"Idempotency-Key": str(uuid4())}
            )
            assert response.status_code == 503, response.text
            assert await client.repairs(inspection["id"]) == []
        finally:
            await fault("warranty", "http-delay", seconds=0)
        print("PASS: real HTTP timeout -> 503, no uncovered repair committed", flush=True)

        before = await client.json("repair", "GET", "/health")
        await fault("repair", "crash-next-consumer")
        await client.complete(inspection["id"], "FAIL")

        async def restarted():
            try:
                health = await client.json("repair", "GET", "/health")
                return health["instance_id"] != before["instance_id"]
            except httpx.HTTPError:
                return False

        await poll(restarted)
        repair = await client.repair(inspection["id"])
        assert len(await client.repairs(inspection["id"])) == 1
        notifications = await client.json("repair", "GET", f"/repairs/{repair['id']}/notifications")
        assert len(notifications) == 1
        print(
            "PASS: actual process crash after DB commit; restarted with one repair/notification",
            flush=True,
        )

        # Uses the default pool capacity: DB_POOL_SIZE + DB_MAX_OVERFLOW = 10.
        holding = asyncio.create_task(fault("vehicle", "hold-db-connections", count=10, seconds=8))
        try:
            await asyncio.sleep(0.5)
            response = await client.request("vehicle", "GET", "/vehicles")
            assert response.status_code == 503, response.text
        finally:
            await holding
        assert (await client.request("vehicle", "GET", "/vehicles")).status_code == 200
        print("PASS: exhausted DB pool returns bounded 503 and recovers", flush=True)
        print("CHAOS DRILLS PASSED", flush=True)
    finally:
        await client.close()
        await redis.aclose()
        for engine in engines.values():
            await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
