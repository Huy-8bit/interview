import asyncio
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.models.warranty import Warranty
from app.schemas.warranty import WarrantyProvision
from app.services.warranties import WarrantyService, create_default, expire_due
from platform_common.db import utcnow
from platform_common.models import OutboxEvent


async def test_rest_retries_and_concurrency_return_same_default_warranty(runtime):
    body = WarrantyProvision(vehicle_id=uuid4(), vehicle_created_at=utcnow())
    svc = WarrantyService(runtime)
    replies = await asyncio.gather(*(svc.provision(body) for _ in range(6)))
    assert len({reply.id for reply in replies}) == 1
    assert (await svc.provision(body)).id == replies[0].id  # Lost-response retry.
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(Warranty)) == 1
        assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 1
    assert runtime.metrics.business["warranties_created_total"]._value.get() == 1


async def test_failed_transaction_rolls_back_warranty_outbox_and_business_counter(runtime):
    body = WarrantyProvision(vehicle_id=uuid4(), vehicle_created_at=utcnow())
    with pytest.raises(RuntimeError):
        async with runtime.sessions.begin() as session:
            await create_default(session, body, runtime)
            raise RuntimeError("crash before commit")
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(Warranty)) == 0
        assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 0
    assert runtime.metrics.business["warranties_created_total"]._value.get() == 0
    await WarrantyService(runtime).provision(body)
    assert runtime.metrics.business["warranties_created_total"]._value.get() == 1


async def test_expiry_changes_coverage_and_emits_event(runtime):
    body = WarrantyProvision(vehicle_id=uuid4(), vehicle_created_at=utcnow()-timedelta(days=runtime.settings.default_warranty_days+2))
    await WarrantyService(runtime).provision(body)
    await expire_due(runtime)
    async with runtime.sessions() as session:
        row = await session.scalar(select(Warranty))
        assert row.status == "EXPIRED"
    assert (await WarrantyService(runtime).coverage(body.vehicle_id)).covered is False
