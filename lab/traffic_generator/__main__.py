import asyncio

from traffic_generator.worker import Traffic

if __name__ == "__main__":
    raise SystemExit(0 if asyncio.run(Traffic().run()) else 1)
