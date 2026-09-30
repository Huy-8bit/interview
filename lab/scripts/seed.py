import argparse
import asyncio

from lab_client import LabClient


async def main(count):
    client = LabClient()
    gate = asyncio.Semaphore(5)

    async def seed_one(index):
        async with gate:
            vehicle = await client.vehicle()
            await client.warranty(vehicle["id"])
            inspection = await client.inspection(vehicle["id"])
            result = "FAIL" if index % 3 == 0 else "PASS"
            await client.complete(inspection["id"], result)
            if result == "FAIL":
                await client.repair(inspection["id"])
            print(f"{index + 1}/{count}: {vehicle['vin']} {result}", flush=True)

    try:
        await asyncio.gather(*(seed_one(i) for i in range(count)))
        print(f"Seeded {count} vehicles, warranties and inspections; {(count + 2) // 3} repairs.")
    finally:
        await client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=100)
    args = parser.parse_args()
    if not 1 <= args.count <= 10000:
        parser.error("count must be 1..10000")
    asyncio.run(main(args.count))
