import logging

from sqlalchemy import select

from app.models.repair import RepairRequest
from app.schemas.repair import FailedInspection, RepairCreate, ReportGenerated
from app.services.repairs import create_in_transaction

log = logging.getLogger(__name__)


async def inspection_failed(session, event, runtime):
    data = FailedInspection.model_validate(event.data)
    await create_in_transaction(
        session,
        runtime,
        RepairCreate(
            vehicle_id=data.vehicle_id,
            inspection_id=data.inspection_id,
            description=data.failure_reason,
        ),
    )


async def inspection_report_generated(session, event, runtime):
    """Attach the defect report to the repair ticket the workshop works from.

    Same Kafka key (vehicle_id) and outbox order as inspection.failed, so the repair
    normally exists already. PASS certificates have no repair and are ignored.
    """
    data = ReportGenerated.model_validate(event.data)
    if data.result != "FAIL":
        return
    repair = await session.scalar(select(RepairRequest).where(RepairRequest.inspection_id == data.inspection_id).with_for_update())
    if repair is None:
        log.warning("defect_report_without_repair", extra={"fields": {"inspection_id": str(data.inspection_id)}})
        return
    repair.defect_report_number, repair.defect_report_sha256 = data.report_number, data.sha256
    repair.defect_report_generated_at = data.generated_at


HANDLERS = {"inspection.failed": inspection_failed, "inspection.report.generated": inspection_report_generated}
