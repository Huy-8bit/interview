import asyncio
import os
from uuid import uuid4

import httpx

URLS = {
    name: os.getenv(name.upper() + "_URL", f"http://{name}-service:8000")
    for name in ("vehicle", "warranty", "inspection", "repair")
}


async def poll(operation, predicate=lambda x: bool(x), timeout=60):
    async with asyncio.timeout(timeout):
        while True:
            value = await operation()
            if predicate(value):
                return value
            await asyncio.sleep(0.25)


class LabClient:
    def __init__(self):
        self.http = httpx.AsyncClient(timeout=30)

    async def close(self):
        await self.http.aclose()

    async def request(self, service, method, path, **kwargs):
        return await self.http.request(method, URLS[service] + path, **kwargs)

    async def json(self, service, method, path, **kwargs):
        response = await self.request(service, method, path, **kwargs)
        response.raise_for_status()
        return response.json()

    async def vehicle(self):
        return await self.json(
            "vehicle",
            "POST",
            "/vehicles",
            json={
                "vin": "LAB" + uuid4().hex[:14].upper(),
                "model": "EV-Lab",
                "manufacturer": "Learning Motors",
                "production_year": 2026,
                "owner_name": "Nguyen Van An",
            },
        )

    async def warranty(self, vehicle_id):
        async def check():
            response = await self.request(
                "warranty", "GET", f"/warranties/vehicle/{vehicle_id}/active"
            )
            if response.status_code == 404:
                return None
            response.raise_for_status()
            return response.json()

        return await poll(check)

    async def inspection(self, vehicle_id, *, key=None, notes="Lab inspection"):
        key = key or str(uuid4())

        async def create():
            response = await self.request(
                "inspection",
                "POST",
                "/inspections",
                headers={"Idempotency-Key": key},
                json={"vehicle_id": vehicle_id, "inspection_type": "DIAGNOSTIC", "notes": notes},
            )
            if (
                response.status_code == 409
                and response.json()["error"]["code"] == "vehicle_projection_not_ready"
            ):
                return None
            response.raise_for_status()
            return response.json()

        return await poll(create)

    async def complete(self, inspection_id, result):
        body = {"result": result}
        if result == "FAIL":
            body["failure_reason"] = "High voltage battery coolant leak"
        return await self.json(
            "inspection", "POST", f"/inspections/{inspection_id}/complete", json=body
        )

    async def repairs(self, inspection_id):
        return await self.json("repair", "GET", "/repairs", params={"inspection_id": inspection_id})

    async def repair(self, inspection_id):
        return (await poll(lambda: self.repairs(inspection_id)))[0]
