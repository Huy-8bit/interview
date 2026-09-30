from sqlalchemy import select

from app.models.inspection import Inspection, VehicleReference
from platform_common.errors import DomainError


async def require_vehicle(session, vehicle_id):
    row = await session.get(VehicleReference, vehicle_id)
    if row is None or not row.vehicle_seen:
        raise DomainError(
            409, "vehicle_projection_not_ready", "vehicle.created has not arrived; retry shortly"
        )


async def get(session, inspection_id, *, lock=False):
    query = select(Inspection).where(Inspection.id == inspection_id)
    if lock:
        query = query.with_for_update()
    row = await session.scalar(query)
    if row is None:
        raise DomainError(404, "inspection_not_found", "Inspection not found")
    return row


async def list_page(session, vehicle_id, limit, offset):
    query = select(Inspection)
    if vehicle_id:
        query = query.where(Inspection.vehicle_id == vehicle_id)
    return (
        await session.scalars(
            query.order_by(Inspection.created_at, Inspection.id).limit(limit).offset(offset)
        )
    ).all()
