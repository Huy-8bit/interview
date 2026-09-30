import asyncio
import json
from uuid import uuid4

from lab_client import LabClient


async def main():
    client = LabClient()
    try:
        vehicle = await client.vehicle()
        print("1. Vehicle created:", vehicle["id"], flush=True)
        warranty = await client.warranty(vehicle["id"])
        print("2. Default warranty:", warranty, flush=True)
        key = str(uuid4())
        inspection = await client.inspection(vehicle["id"], key=key)
        retry = await client.inspection(vehicle["id"], key=key)
        assert retry == inspection
        print(
            "3. Inspection created; identical retry returned the same resource:",
            inspection["id"],
            flush=True,
        )
        await client.complete(inspection["id"], "FAIL")
        print("4. Inspection failed; waiting for Kafka -> warranty REST -> repair...", flush=True)
        repair = await client.repair(inspection["id"])
        notifications = await client.json("repair", "GET", f"/repairs/{repair['id']}/notifications")
        passed = await client.inspection(vehicle["id"])
        await client.complete(passed["id"], "PASS")
        print(
            json.dumps(
                {
                    "vehicle": vehicle,
                    "warranty": warranty,
                    "failed_inspection_id": inspection["id"],
                    "repair": repair,
                    "notifications": notifications,
                    "passed_inspection_id": passed["id"],
                },
                indent=2,
            )
        )
        assert repair["warranty_covered"] and len(notifications) == 1
        print("DEMO PASSED", flush=True)
    finally:
        await client.close()


if __name__ == "__main__":
    asyncio.run(main())
