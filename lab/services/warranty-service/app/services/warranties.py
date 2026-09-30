import asyncio
import logging
from datetime import timedelta
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert

from app.models.warranty import Warranty
from app.repositories import warranties as repository
from app.schemas.warranty import Coverage, WarrantyRead
from platform_common.db import utcnow
from platform_common.errors import DomainError
from platform_common.events import enqueue

log = logging.getLogger(__name__)


def emit(session, runtime, row, kind):
    result = WarrantyRead.model_validate(row).model_dump(mode="json")
    enqueue(session, runtime.settings, kind, row.vehicle_id, result)
    return result


async def create_default(session, event, runtime):
    vehicle_id = UUID(event.data["id"])
    # Event time makes the dates deterministic even if processing is delayed.
    start = event.occurred_at.date()
    async with runtime.cache.lock(f"default-warranty:{vehicle_id}"):
        row = await session.scalar(
            insert(Warranty)
            .values(
                id=uuid4(),
                vehicle_id=vehicle_id,
                warranty_type="DEFAULT",
                start_date=start,
                end_date=start + timedelta(days=runtime.settings.default_warranty_days),
                status="ACTIVE",
            )
            .on_conflict_do_nothing(constraint="uq_warranty_vehicle_type")
            .returning(Warranty)
        )
        if row:
            emit(session, runtime, row, "warranty.created")


class WarrantyService:
    def __init__(self, runtime):
        self.runtime = runtime

    async def list(self, vehicle_id):
        async with self.runtime.sessions() as session:
            return [
                WarrantyRead.model_validate(w)
                for w in await repository.for_vehicle(session, vehicle_id)
            ]

    async def coverage(self, vehicle_id):
        if self.runtime.http_delay:
            await asyncio.sleep(self.runtime.http_delay)
        async with self.runtime.sessions() as session:
            rows = await repository.for_vehicle(session, vehicle_id)
            if not rows:
                raise DomainError(
                    404,
                    "warranty_not_ready",
                    "No warranty history yet; vehicle event may still be in transit",
                )
            today = utcnow().date()
            active = next(
                (w for w in rows if w.status == "ACTIVE" and w.start_date <= today <= w.end_date),
                None,
            )
            return Coverage(
                vehicle_id=vehicle_id,
                covered=active is not None,
                warranty_id=active.id if active else None,
                checked_at=utcnow(),
            )

    async def create(self, body):
        async with self.runtime.sessions.begin() as session:
            if not await repository.for_vehicle(session, body.vehicle_id):
                raise DomainError(
                    409, "vehicle_not_ready", "Wait for default warranty from vehicle.created"
                )
            row = Warranty(**body.model_dump())
            session.add(row)
            await session.flush()
            return emit(session, self.runtime, row, "warranty.created")

    async def transition(self, warranty_id, status):
        async with self.runtime.sessions.begin() as session:
            row = await repository.get(session, warranty_id)
            if row.status == status:
                return WarrantyRead.model_validate(row)
            if status == "ACTIVE" and (
                row.status != "PENDING" or not row.start_date <= utcnow().date() <= row.end_date
            ):
                raise DomainError(
                    409,
                    "invalid_transition",
                    "Only a PENDING warranty within its date range can activate",
                )
            row.status = status
            await session.flush()
            return emit(
                session,
                self.runtime,
                row,
                "warranty.activated" if status == "ACTIVE" else "warranty.expired",
            )


async def expire_due(runtime):
    async with runtime.sessions.begin() as session:
        rows = (
            await session.scalars(
                select(Warranty)
                .where(
                    Warranty.status.in_(["ACTIVE", "PENDING"]),
                    Warranty.end_date < utcnow().date(),
                )
                .limit(100)
                .with_for_update(skip_locked=True)
            )
        ).all()
        for row in rows:
            row.status = "EXPIRED"
            await session.flush()
            emit(session, runtime, row, "warranty.expired")


async def expiry_loop(runtime):
    while True:
        try:
            await expire_due(runtime)
        except Exception:
            log.exception("warranty_expiry_retry")
        await asyncio.sleep(runtime.settings.warranty_expiry_interval)
