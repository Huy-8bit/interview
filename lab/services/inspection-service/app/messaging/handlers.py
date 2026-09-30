from uuid import UUID

from sqlalchemy.dialects.postgresql import insert

from app.models.inspection import VehicleReference
from platform_common.db import utcnow


async def update_reference(session, event, runtime):
    is_vehicle = event.event_type == "vehicle.created"
    vehicle_id = UUID(event.data["id"] if is_vehicle else event.data["vehicle_id"])
    flag = "vehicle_seen" if is_vehicle else "warranty_seen"
    await session.execute(
        insert(VehicleReference)
        .values(
            vehicle_id=vehicle_id,
            vehicle_seen=is_vehicle,
            warranty_seen=not is_vehicle,
        )
        .on_conflict_do_update(
            index_elements=["vehicle_id"], set_={flag: True, "updated_at": utcnow()}
        )
    )


HANDLERS = {"vehicle.created": update_reference, "warranty.created": update_reference}
