from uuid import UUID, uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.schemas.vehicle import VehicleCreate, VehicleUpdate
from app.services.vehicles import VehicleService
from platform_common.models import OutboxEvent


async def test_vehicle_unique_vin_cache_invalidation_and_atomic_outbox(runtime):
    service = VehicleService(runtime)
    payload = VehicleCreate(
        vin="LAB" + uuid4().hex[:14].upper(),
        model="EV",
        manufacturer="Lab",
        production_year=2026,
        owner_name="An",
    )
    vehicle = await service.create(payload)
    vehicle_id = UUID(vehicle["id"])
    async with runtime.sessions() as session:
        event = await session.scalar(select(OutboxEvent))
        assert event.event_type == "vehicle.created"
        assert event.payload["data"]["id"] == vehicle["id"]
    with pytest.raises(IntegrityError):
        await service.create(payload)
    first, cache = await service.get(vehicle_id)
    assert cache == "MISS"
    assert (await service.get(vehicle_id))[1] == "HIT"
    await service.update(vehicle_id, VehicleUpdate(owner_name="Binh"))
    updated, cache = await service.get(vehicle_id)
    assert cache == "MISS" and updated["owner_name"] == "Binh"
    assert first["owner_name"] == "An"


async def test_cache_generation_prevents_late_stale_fill(runtime):
    key = "vehicle:test:" + uuid4().hex
    _, old_generation = await runtime.cache.cache_read(key)
    await runtime.cache.invalidate(key)
    await runtime.cache.cache_fill(key, {"owner_name": "stale"}, old_generation)
    assert (await runtime.cache.cache_read(key))[0] is None
    await runtime.redis.delete(key, key + ":generation")
