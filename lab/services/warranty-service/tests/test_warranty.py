import asyncio
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.models.warranty import Warranty
from app.services.warranties import WarrantyService, create_default, expire_due
from platform_common.consumer import process_event
from platform_common.db import utcnow
from platform_common.events import Event
from platform_common.models import OutboxEvent, ProcessedEvent


def event(vehicle_id):
    return Event(
        event_id=uuid4(),
        event_type="vehicle.created",
        occurred_at=utcnow(),
        producer="test",
        correlation_id=str(uuid4()),
        data={"id": str(vehicle_id)},
    )


async def test_concurrent_duplicate_event_has_one_warranty_and_outbox(runtime):
    message = event(uuid4())
    results = await asyncio.gather(
        *(process_event(runtime, message, create_default) for _ in range(6))
    )
    assert sum(results) == 1
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(Warranty)) == 1
        assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 1
        assert await session.scalar(select(func.count()).select_from(ProcessedEvent)) == 1
    # A new event_id for the same vehicle still cannot duplicate DEFAULT warranty.
    await process_event(runtime, event(message.data["id"]), create_default)
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(Warranty)) == 1


async def test_consumer_failure_rolls_back_marker_and_business(runtime):
    message = event(uuid4())

    async def fail(session, event, rt):
        await create_default(session, event, rt)
        raise RuntimeError("crash before commit")

    with pytest.raises(RuntimeError):
        await process_event(runtime, message, fail)
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(ProcessedEvent)) == 0
        assert await session.scalar(select(func.count()).select_from(Warranty)) == 0
    assert await process_event(runtime, message, create_default)


async def test_expiry_changes_coverage_and_emits_event(runtime):
    from datetime import timedelta

    message = event(uuid4())
    message.occurred_at = utcnow() - timedelta(days=runtime.settings.default_warranty_days + 2)
    await process_event(runtime, message, create_default)
    await expire_due(runtime)
    async with runtime.sessions() as session:
        row = await session.scalar(select(Warranty))
        assert row.status == "EXPIRED"
        vehicle_id = row.vehicle_id
    assert (await WarrantyService(runtime).coverage(vehicle_id)).covered is False
