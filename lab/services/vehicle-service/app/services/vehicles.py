import logging

from app.models.vehicle import Vehicle
from app.repositories import vehicles as repository
from app.schemas.vehicle import VehicleRead
from platform_common.events import enqueue

log = logging.getLogger(__name__)


class VehicleService:
    def __init__(self, runtime):
        self.runtime = runtime

    async def create(self, body):
        async with self.runtime.sessions.begin() as session:
            vehicle = Vehicle(**body.model_dump())
            session.add(vehicle)
            await session.flush()
            result = VehicleRead.model_validate(vehicle).model_dump(mode="json")
            enqueue(session, self.runtime.settings, "vehicle.created", vehicle.id, result)
        return result

    async def get(self, vehicle_id):
        key = f"vehicle:{vehicle_id}"
        cached, generation = await self.runtime.cache.cache_read(key)
        if cached:
            log.info("vehicle_cache_hit")
            return cached, "HIT"
        async with self.runtime.sessions() as session:
            vehicle = await repository.get(session, vehicle_id)
            result = VehicleRead.model_validate(vehicle).model_dump(mode="json")
        await self.runtime.cache.cache_fill(key, result, generation)
        log.info("vehicle_cache_miss")
        return result, "MISS"

    async def update(self, vehicle_id, body):
        async with self.runtime.sessions.begin() as session:
            vehicle = await repository.get(session, vehicle_id, lock=True)
            for key, value in body.model_dump(exclude_unset=True).items():
                setattr(vehicle, key, value)
            await session.flush()
            result = VehicleRead.model_validate(vehicle).model_dump(mode="json")
            enqueue(session, self.runtime.settings, "vehicle.updated", vehicle.id, result)
        await self.runtime.cache.invalidate(f"vehicle:{vehicle_id}")
        return result

    async def list(self, limit, offset):
        async with self.runtime.sessions() as session:
            return [
                VehicleRead.model_validate(v)
                for v in await repository.list_page(session, limit, offset)
            ]
