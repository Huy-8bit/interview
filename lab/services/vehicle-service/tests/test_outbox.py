from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select, update

from platform_common.db import utcnow
from platform_common.events import enqueue
from platform_common.models import OutboxEvent
from platform_common.outbox import publish_one


async def test_outbox_retry_then_real_kafka_ack(runtime):
    async with runtime.sessions.begin() as session:
        enqueue(session, runtime.settings, "vehicle.updated", uuid4(), {"test": True})
    runtime.outbox_failures = 1
    assert await publish_one(runtime)
    async with runtime.sessions.begin() as session:
        event = await session.scalar(select(OutboxEvent))
        assert event.status == "PENDING" and event.attempts == 1 and event.published_at is None
        event.next_attempt_at = utcnow() - timedelta(seconds=1)
    assert await publish_one(runtime)
    async with runtime.sessions() as session:
        event = await session.scalar(select(OutboxEvent))
        assert event.status == "PUBLISHED" and event.published_at is not None


async def test_business_rollback_removes_outbox(runtime):
    with pytest.raises(RuntimeError):
        async with runtime.sessions.begin() as session:
            enqueue(session, runtime.settings, "vehicle.updated", uuid4(), {})
            await session.flush()
            raise RuntimeError("business operation failed")
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 0


async def test_later_event_cannot_overtake_retrying_aggregate(runtime):
    aggregate = uuid4()
    async with runtime.sessions.begin() as session:
        first = enqueue(session, runtime.settings, "vehicle.updated", aggregate, {"version": 1})
        enqueue(session, runtime.settings, "vehicle.updated", aggregate, {"version": 2})
        await session.flush()
        await session.execute(
            update(OutboxEvent)
            .where(OutboxEvent.event_id == first.event_id)
            .values(next_attempt_at=utcnow() + timedelta(minutes=1))
        )
    assert await publish_one(runtime) is False
