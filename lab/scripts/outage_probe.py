import argparse
import asyncio
import os
from uuid import uuid4

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from lab_client import LabClient, poll


async def query(service, sql, **params):
    engine = create_async_engine(os.environ[service.upper() + "_DATABASE_URL"])
    try:
        async with engine.connect() as connection:
            return (await connection.execute(text(sql), params)).mappings().all()
    finally:
        await engine.dispose()


async def main(component):
    client = LabClient()
    try:
        if component == "postgres":
            assert (await client.request("vehicle", "GET", "/health")).status_code == 200
            assert (await client.request("vehicle", "GET", "/ready")).status_code == 503
            assert (await client.request("vehicle", "GET", "/vehicles")).status_code == 503
        elif component == "kafka":
            vehicle = await client.vehicle()
            await asyncio.sleep(6)
            rows = await query(
                "vehicle",
                "SELECT status, attempts FROM outbox_events WHERE aggregate_id=:id",
                id=vehicle["id"],
            )
            assert rows[0]["status"] == "PENDING" and rows[0]["attempts"] >= 1
        elif component == "redis":
            vehicle = await client.vehicle()
            assert (await client.json("vehicle", "GET", f"/vehicles/{vehicle['id']}"))[
                "id"
            ] == vehicle["id"]
            await client.warranty(vehicle["id"])
            key = str(uuid4())
            first = await client.inspection(vehicle["id"], key=key)
            assert await client.inspection(vehicle["id"], key=key) == first
        elif component == "warranty-service":
            rows = await query(
                "warranty", "SELECT vehicle_id FROM warranties WHERE status='ACTIVE' LIMIT 1"
            )
            if not rows:
                raise SystemExit("Run make demo first to prepare a vehicle")
            inspection_id = str(uuid4())
            response = await client.request(
                "repair",
                "POST",
                "/repairs",
                headers={"Idempotency-Key": str(uuid4())},
                json={
                    "vehicle_id": str(rows[0]["vehicle_id"]),
                    "inspection_id": inspection_id,
                    "description": "Outage drill",
                },
            )
            assert response.status_code == 503, response.text
            assert await client.repairs(inspection_id) == []
        elif component == "recovery":

            async def healthy():
                responses = await asyncio.gather(
                    *(
                        client.request(s, "GET", "/ready")
                        for s in ("vehicle", "warranty", "inspection", "repair")
                    ),
                    return_exceptions=True,
                )
                return all(
                    isinstance(r, httpx.Response) and r.status_code == 200 for r in responses
                )

            await poll(healthy, timeout=90)

            async def drained():
                rows = await query(
                    "vehicle",
                    "SELECT count(*) AS pending FROM outbox_events WHERE status='PENDING'",
                )
                return rows[0]["pending"] == 0

            await poll(drained, timeout=90)
        print(f"PASS: {component}", flush=True)
    finally:
        await client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "component", choices=["postgres", "redis", "kafka", "warranty-service", "recovery"]
    )
    asyncio.run(main(parser.parse_args().component))
