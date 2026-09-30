from sqlalchemy import select

from app.models.vehicle import Vehicle
from platform_common.errors import DomainError


async def get(session, vehicle_id, *, lock=False):
    query = select(Vehicle).where(Vehicle.id == vehicle_id)
    if lock:
        query = query.with_for_update()
    vehicle = await session.scalar(query)
    if vehicle is None:
        raise DomainError(404, "vehicle_not_found", "Vehicle not found")
    return vehicle


async def list_page(session, limit, offset):
    return (
        await session.scalars(
            select(Vehicle).order_by(Vehicle.created_at, Vehicle.id).limit(limit).offset(offset)
        )
    ).all()
