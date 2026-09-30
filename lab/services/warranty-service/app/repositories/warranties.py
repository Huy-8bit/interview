from sqlalchemy import select

from app.models.warranty import Warranty
from platform_common.errors import DomainError


async def get(session, warranty_id):
    row = await session.scalar(select(Warranty).where(Warranty.id == warranty_id).with_for_update())
    if row is None:
        raise DomainError(404, "warranty_not_found", "Warranty not found")
    return row


async def for_vehicle(session, vehicle_id):
    return (
        await session.scalars(
            select(Warranty).where(Warranty.vehicle_id == vehicle_id).order_by(Warranty.created_at)
        )
    ).all()
