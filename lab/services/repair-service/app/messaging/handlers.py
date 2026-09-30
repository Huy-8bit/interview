from app.schemas.repair import FailedInspection, RepairCreate
from app.services.repairs import create_in_transaction


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


HANDLERS = {"inspection.failed": inspection_failed}
