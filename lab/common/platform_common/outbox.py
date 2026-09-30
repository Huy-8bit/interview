import asyncio
import logging
from datetime import timedelta

from sqlalchemy import exists, select
from sqlalchemy.orm import aliased

from platform_common import context
from platform_common.db import utcnow
from platform_common.models import OutboxEvent

log = logging.getLogger(__name__)


def backoff(attempt: int, base: float = 1, cap: float = 60) -> float:
    return min(cap, base * 2 ** min(attempt, 16))


async def publish_one(runtime) -> bool:
    """A row lock is held until ACK and DB commit; crashes may redeliver, never erase intent."""
    older = aliased(OutboxEvent)
    async with runtime.sessions.begin() as session:
        row = await session.scalar(
            select(OutboxEvent)
            .where(
                OutboxEvent.status == "PENDING",
                OutboxEvent.next_attempt_at <= utcnow(),
                ~exists(
                    select(older.id).where(
                        older.aggregate_id == OutboxEvent.aggregate_id,
                        older.status == "PENDING",
                        older.id < OutboxEvent.id,
                    )
                ),
            )
            .order_by(OutboxEvent.id)
            .limit(1)
            .with_for_update(skip_locked=True)
        )
        if row is None:
            return False
        ct = context.correlation_id.set(row.payload["correlation_id"])
        et = context.event_id.set(str(row.event_id))
        try:
            if runtime.outbox_failures > 0:
                runtime.outbox_failures -= 1
                raise ConnectionError("lab: injected outbox publish failure")
            await runtime.publisher.publish(row.topic, row.aggregate_id, row.payload)
        except Exception as exc:
            row.attempts += 1
            row.last_error = str(exc)[:2000]
            row.next_attempt_at = utcnow() + timedelta(
                seconds=backoff(
                    row.attempts - 1,
                    runtime.settings.retry_base_seconds,
                    runtime.settings.outbox_retry_max_seconds,
                )
            )
            log.warning(
                "outbox_publish_retry",
                extra={"fields": {"attempt": row.attempts, "error": row.last_error}},
            )
        else:
            row.status, row.published_at, row.last_error = "PUBLISHED", utcnow(), None
            log.info(
                "outbox_published",
                extra={"fields": {"topic": row.topic, "event_type": row.event_type}},
            )
        finally:
            context.correlation_id.reset(ct)
            context.event_id.reset(et)
    return True


async def outbox_loop(runtime):
    while True:
        try:
            found = await publish_one(runtime)
            if not found:
                await asyncio.sleep(runtime.settings.outbox_interval)
        except Exception:
            log.exception("outbox_iteration_failed")
            await asyncio.sleep(runtime.settings.outbox_interval)
