import logging
from uuid import uuid4

from sqlalchemy.dialects.postgresql import insert

from app.infrastructure.warranty_client import check_coverage
from app.models.repair import Notification, RepairRequest
from app.repositories import repairs as repository
from app.schemas.repair import NotificationRead, RepairRead
from platform_common.errors import DomainError
from platform_common.events import enqueue
from platform_common.idempotency import execute_idempotent

log = logging.getLogger(__name__)


def serialize(row):
    return RepairRead.model_validate(row).model_dump(mode="json")


def verify_vehicle(row, body):
    if row.vehicle_id != body.vehicle_id:
        raise DomainError(
            409, "inspection_vehicle_conflict", "Inspection already associated with another vehicle"
        )


async def create_in_transaction(session, runtime, body):
    existing = await repository.by_inspection(session, body.inspection_id)
    if existing:
        verify_vehicle(existing, body)
        return serialize(existing)
    async with runtime.cache.lock(f"repair:{body.inspection_id}"):
        covered = await check_coverage(runtime, body.vehicle_id)
        row = await session.scalar(
            insert(RepairRequest)
            .values(
                id=uuid4(),
                **body.model_dump(),
                warranty_covered=covered,
                status="OPEN",
            )
            .on_conflict_do_nothing(index_elements=["inspection_id"])
            .returning(RepairRequest)
        )
        if row is None:
            existing = await repository.by_inspection(session, body.inspection_id)
            verify_vehicle(existing, body)
            return serialize(existing)
        notification = Notification(
            vehicle_id=row.vehicle_id,
            repair_id=row.id,
            message=f"Repair {row.id} opened. Warranty covered: {covered}.",
        )
        session.add(notification)
        await session.flush()
        result = serialize(row)
        enqueue(session, runtime.settings, "repair.created", row.vehicle_id, result)
        # DB record is authoritative. A log may precede commit and is not delivery proof.
        log.info(
            "notification_staged",
            extra={"fields": {"repair_id": str(row.id), "notification_id": str(notification.id)}},
        )
        return result


class RepairService:
    def __init__(self, runtime):
        self.runtime = runtime

    async def create(self, body, key):
        async def action(session):
            return await create_in_transaction(session, self.runtime, body)

        return await execute_idempotent(
            self.runtime, "POST:/repairs", key, body.model_dump(mode="json"), action
        )

    async def get(self, repair_id):
        async with self.runtime.sessions() as session:
            return serialize(await repository.get(session, repair_id))

    async def list(self, vehicle_id, inspection_id, limit, offset):
        async with self.runtime.sessions() as session:
            return [
                serialize(r)
                for r in await repository.list_page(
                    session, vehicle_id, inspection_id, limit, offset
                )
            ]

    async def notifications(self, repair_id):
        async with self.runtime.sessions() as session:
            return [
                NotificationRead.model_validate(n)
                for n in await repository.notifications(session, repair_id)
            ]

    async def update(self, repair_id, status):
        async with self.runtime.sessions.begin() as session:
            row = await repository.get(session, repair_id, lock=True)
            allowed = {
                "OPEN": {"IN_PROGRESS", "CANCELLED"},
                "IN_PROGRESS": {"COMPLETED", "CANCELLED"},
                "COMPLETED": set(),
                "CANCELLED": set(),
            }
            if row.status != status and status not in allowed[row.status]:
                raise DomainError(
                    409, "invalid_transition", f"Cannot move repair from {row.status} to {status}"
                )
            row.status = status
            await session.flush()
            return serialize(row)
