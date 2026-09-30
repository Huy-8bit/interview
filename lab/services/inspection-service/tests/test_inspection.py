import asyncio
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select

from app.messaging.handlers import update_reference
from app.models.inspection import Inspection, VehicleReference
from app.schemas.inspection import InspectionComplete, InspectionCreate
from app.services.inspections import InspectionService
from platform_common.consumer import process_event
from platform_common.db import utcnow
from platform_common.errors import DomainError
from platform_common.events import Event
from platform_common.models import OutboxEvent


async def reference(runtime):
    vehicle_id = uuid4()
    # Deliberately reversed cross-topic order.
    for kind, data in [
        ("warranty.created", {"vehicle_id": str(vehicle_id)}),
        ("vehicle.created", {"id": str(vehicle_id)}),
    ]:
        event = Event(
            event_id=uuid4(),
            event_type=kind,
            occurred_at=utcnow(),
            producer="test",
            correlation_id=str(uuid4()),
            data=data,
        )
        await process_event(runtime, event, update_reference)
    async with runtime.sessions() as session:
        row = await session.get(VehicleReference, vehicle_id)
        assert row.vehicle_seen and row.warranty_seen
    return vehicle_id


async def test_concurrent_idempotency_and_redis_eviction(runtime):
    service = InspectionService(runtime)
    body = InspectionCreate(vehicle_id=await reference(runtime))
    key = str(uuid4())
    results = await asyncio.gather(*(service.create(body, key) for _ in range(6)))
    assert len({row["id"] for row in results}) == 1
    keys = [key async for key in runtime.redis.scan_iter(f"idem:{runtime.settings.service_name}:*")]
    if keys:
        await runtime.redis.delete(*keys)
    assert await service.create(body, key) == results[0]
    with pytest.raises(DomainError) as error:
        await service.create(body.model_copy(update={"notes": "changed"}), key)
    assert error.value.status == 409
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(Inspection)) == 1


async def test_completion_is_atomic_and_repeat_does_not_emit_again(runtime):
    service = InspectionService(runtime)
    created = await service.create(
        InspectionCreate(vehicle_id=await reference(runtime)), str(uuid4())
    )
    identity = UUID(created["id"])
    complete = InspectionComplete(result="FAIL", failure_reason="brake defect")
    first = await service.complete(identity, complete)
    assert await service.complete(identity, complete) == first
    with pytest.raises(DomainError):
        await service.complete(identity, InspectionComplete(result="PASS"))
    async with runtime.sessions() as session:
        rows = (await session.scalars(select(OutboxEvent))).all()
        assert len(rows) == 1 and rows[0].event_type == "inspection.failed"
        assert set(rows[0].payload["data"]) == {
            "inspection_id",
            "vehicle_id",
            "failure_reason",
            "occurred_at",
        }
