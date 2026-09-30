from sqlalchemy import select
from sqlalchemy.orm import undefer

from app.models.inspection import Inspection, InspectionReport
from app.reports.celery_app import HIGH_PRIORITY, NORMAL_PRIORITY
from app.repositories import inspections as repository
from app.schemas.inspection import InspectionRead, ReportRead
from platform_common import context
from platform_common.db import utcnow
from platform_common.errors import DomainError
from platform_common.events import enqueue
from platform_common.idempotency import execute_idempotent
from platform_common.metrics import committed


def serialize(row):
    return InspectionRead.model_validate(row).model_dump(mode="json")


class InspectionService:
    def __init__(self, runtime):
        self.runtime = runtime

    async def create(self, body, key):
        async def action(session):
            reference = await repository.require_vehicle(session, body.vehicle_id)
            row = Inspection(**body.model_dump(), warranty_id=reference.warranty_id)
            session.add(row)
            await session.flush()
            committed(session, self.runtime.metrics.business["inspections_created_total"])
            return serialize(row)

        return await execute_idempotent(
            self.runtime, "POST:/inspections", key, body.model_dump(mode="json"), action
        )

    async def get(self, inspection_id):
        async with self.runtime.sessions() as session:
            return serialize(await repository.get(session, inspection_id))

    async def list(self, vehicle_id, limit, offset):
        async with self.runtime.sessions() as session:
            return [
                serialize(row)
                for row in await repository.list_page(session, vehicle_id, limit, offset)
            ]

    async def update(self, inspection_id, body):
        async with self.runtime.sessions.begin() as session:
            row = await repository.get(session, inspection_id, lock=True)
            if row.status == "COMPLETED":
                raise DomainError(409, "inspection_completed", "Completed inspection is immutable")
            for field, value in body.model_dump(exclude_unset=True).items():
                setattr(row, field, value)
            await session.flush()
            return serialize(row)

    async def complete(self, inspection_id, body):
        async with self.runtime.sessions.begin() as session:
            row = await repository.get(session, inspection_id, lock=True)
            if row.status == "COMPLETED":
                if (
                    row.result != body.result
                    or row.failure_reason != body.failure_reason
                    or ("notes" in body.model_fields_set and row.notes != body.notes)
                ):
                    raise DomainError(
                        409,
                        "completion_conflict",
                        "Inspection already completed with a different result",
                    )
                return serialize(row)
            row.status, row.result, row.failure_reason = (
                "COMPLETED",
                body.result,
                body.failure_reason,
            )
            committed(session, self.runtime.metrics.business["inspections_passed_total" if body.result == "PASS" else "inspections_failed_total"])
            row.completed_at = utcnow()
            if "notes" in body.model_fields_set:
                row.notes = body.notes
            # Same transaction as the result: the report request cannot be lost or
            # created for an uncommitted result. A defect report gates the repair
            # workshop, so it jumps ahead of PASS certificates in the queue.
            failed = body.result == "FAIL"
            session.add(InspectionReport(
                inspection_id=row.id, vehicle_id=row.vehicle_id,
                kind="DEFECT_REPORT" if failed else "CERTIFICATE",
                priority=HIGH_PRIORITY if failed else NORMAL_PRIORITY,
                correlation_id=context.correlation_id.get(),
            ))
            await session.flush()
            enqueue(
                session,
                self.runtime.settings,
                "inspection.passed" if body.result == "PASS" else "inspection.failed",
                row.vehicle_id,
                {
                    "inspection_id": str(row.id),
                    "vehicle_id": str(row.vehicle_id),
                    "warranty_id": str(row.warranty_id) if row.warranty_id else None,
                    "failure_reason": row.failure_reason,
                    "occurred_at": row.completed_at.isoformat(),
                },
            )
            return serialize(row)

    async def report(self, inspection_id, *, document=False):
        async with self.runtime.sessions() as session:
            query = select(InspectionReport).where(InspectionReport.inspection_id == inspection_id)
            if document:
                query = query.options(undefer(InspectionReport.document))
            row = await session.scalar(query)
        if row is None:
            await self.get(inspection_id)  # 404 inspection_not_found when the inspection itself is missing
            raise DomainError(404, "report_not_found", "Reports exist only for inspections completed after reports were enabled")
        if document and row.status != "GENERATED":
            raise DomainError(409, "report_not_ready", f"Report is {row.status}; retry after it is GENERATED")
        return row if document else ReportRead.model_validate(row).model_dump(mode="json")
