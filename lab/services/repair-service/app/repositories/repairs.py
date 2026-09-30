from sqlalchemy import select

from app.models.repair import Notification, RepairRequest
from platform_common.errors import DomainError


async def get(session, repair_id, *, lock=False):
    query = select(RepairRequest).where(RepairRequest.id == repair_id)
    if lock:
        query = query.with_for_update()
    row = await session.scalar(query)
    if row is None:
        raise DomainError(404, "repair_not_found", "Repair not found")
    return row


async def by_inspection(session, inspection_id):
    return await session.scalar(
        select(RepairRequest).where(RepairRequest.inspection_id == inspection_id)
    )


async def list_page(session, vehicle_id, inspection_id, limit, offset):
    query = select(RepairRequest)
    if vehicle_id:
        query = query.where(RepairRequest.vehicle_id == vehicle_id)
    if inspection_id:
        query = query.where(RepairRequest.inspection_id == inspection_id)
    return (
        await session.scalars(
            query.order_by(RepairRequest.created_at, RepairRequest.id).limit(limit).offset(offset)
        )
    ).all()


async def notifications(session, repair_id):
    await get(session, repair_id)
    return (
        await session.scalars(select(Notification).where(Notification.repair_id == repair_id))
    ).all()
