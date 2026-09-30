import logging

from app.models.vehicle import Vehicle, WarrantyProvisionRequest
from app.repositories import vehicles as repository
from app.schemas.vehicle import VehicleRead
from app.services.warranty_provision import deliver_pending
from platform_common.errors import DomainError
from platform_common.events import enqueue
from platform_common.metrics import committed
from platform_common.redis import vehicle_cache_key

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
            event = enqueue(session, self.runtime.settings, "vehicle.created", vehicle.id, result)
            session.add(WarrantyProvisionRequest(vehicle_id=vehicle.id, correlation_id=event.correlation_id, created_at=vehicle.created_at))
            committed(session, self.runtime.metrics.business["vehicles_created_total"])
        try:
            await deliver_pending(self.runtime, vehicle.id)
        except Exception:
            # Local commit already succeeded; the durable worker will retry.
            log.exception("warranty_provision_deferred")
        return result

    async def get(self, vehicle_id):
        key = vehicle_cache_key(vehicle_id)
        cached, generation = await self.runtime.cache.cache_read(key)
        if cached:
            self.runtime.metrics.business["vehicle_cache_hit_total"].inc()
            log.info("vehicle_cache_hit")
            return cached, "HIT"
        self.runtime.metrics.business["vehicle_cache_miss_total"].inc()
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
        await self.runtime.cache.invalidate(vehicle_cache_key(vehicle_id))
        return result

    async def get_eventual(self, vehicle_id):
        async def read(session):
            vehicle = await repository.get(session, vehicle_id)
            return VehicleRead.model_validate(vehicle).model_dump(mode="json")

        return await self.runtime.read(read)

    async def delete_simulation(self, vehicle_id, run_id):
        async with self.runtime.sessions.begin() as session:
            vehicle = await repository.get(session, vehicle_id, lock=True)
            if vehicle.simulation_run_id != run_id or not vehicle.vin.startswith("TRF"):
                raise DomainError(403, "simulation_delete_forbidden", "Only this simulation run's vehicles can be deleted")
            await session.delete(vehicle)
        await self.runtime.cache.invalidate(vehicle_cache_key(vehicle_id))

    async def list(self, limit, offset, vin=None):
        async with self.runtime.sessions() as session:
            return [
                VehicleRead.model_validate(v)
                for v in await repository.list_page(session, limit, offset, vin)
            ]
