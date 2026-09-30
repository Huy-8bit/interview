from uuid import UUID, uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.schemas.vehicle import VehicleCreate, VehicleUpdate
from app.services.vehicles import VehicleService
from platform_common.models import OutboxEvent
from platform_common.redis import vehicle_cache_key


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
    key = vehicle_cache_key(uuid4())
    _, old_generation = await runtime.cache.cache_read(key)
    assert old_generation is not None  # A CROSSSLOT error must not silently turn this into a no-op.
    await runtime.cache.invalidate(key)
    await runtime.cache.cache_fill(key, {"owner_name": "stale"}, old_generation)
    assert (await runtime.cache.cache_read(key))[0] is None
    await runtime.redis.delete(key, key + ":generation")


async def test_simulation_delete_requires_persisted_matching_marker(runtime):
    from platform_common.errors import DomainError

    service = VehicleService(runtime)
    run_id = uuid4()
    ordinary = await service.create(VehicleCreate(vin="LAB" + uuid4().hex[:14].upper(), model="EV", manufacturer="Lab", production_year=2026, owner_name="Ordinary"))
    with pytest.raises(DomainError) as denied:
        await service.delete_simulation(UUID(ordinary["id"]), run_id)
    assert denied.value.status == 403
    marked = await service.create(VehicleCreate(vin="TRF" + uuid4().hex[:14].upper(), model="EV", manufacturer="Lab", production_year=2026, owner_name="Synthetic", simulation_run_id=run_id))
    marked_id = UUID(marked["id"])
    await service.get(marked_id)
    with pytest.raises(DomainError):
        await service.delete_simulation(marked_id, uuid4())
    await service.delete_simulation(marked_id, run_id)
    with pytest.raises(DomainError) as absent:
        await service.get(marked_id)
    assert absent.value.status == 404
    assert (await service.get(UUID(ordinary["id"])))[0]["id"] == ordinary["id"]
    assert len(await service.list(20, 0, ordinary["vin"])) == 1
