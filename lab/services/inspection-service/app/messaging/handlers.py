import logging
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert

from app.models.inspection import VehicleReference, VehicleWarrantyProjection
from platform_common.db import utcnow
from platform_common.metrics import committed

log = logging.getLogger(__name__)


async def lock_vehicle(session, vehicle_id):
    # Transaction lock serializes BOTH paths even before a reference row exists.
    await session.execute(text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"), {"key": str(vehicle_id)})


async def try_prepare_inspection(session, vehicle_id):
    reference = await session.get(VehicleReference, vehicle_id)
    warranty = await session.scalar(select(VehicleWarrantyProjection).where(
        VehicleWarrantyProjection.vehicle_id == vehicle_id, VehicleWarrantyProjection.is_deleted.is_(False)
    ).order_by(VehicleWarrantyProjection.warranty_type, VehicleWarrantyProjection.warranty_id).limit(1))
    reference.warranty_seen = warranty is not None
    reference.warranty_id = warranty.warranty_id if warranty else None
    reference.workflow_status = "WAITING_VEHICLE" if not reference.vehicle_seen else "WAITING_WARRANTY" if not warranty else "READY"
    if reference.workflow_status == "READY" and reference.prepared_at is None:
        reference.prepared_at = utcnow()


async def update_reference(session, event, runtime):
    vehicle_id = UUID(event.data["id"])
    await lock_vehicle(session, vehicle_id)
    stmt = insert(VehicleReference).values(vehicle_id=vehicle_id, vehicle_seen=True, warranty_seen=False,
                                          vehicle_payload=event.data, source_updated_at=event.occurred_at)
    await session.execute(stmt.on_conflict_do_update(index_elements=["vehicle_id"],
        set_={"vehicle_seen": True, "vehicle_payload": event.data, "source_updated_at": event.occurred_at, "updated_at": utcnow()},
        where=(VehicleReference.source_updated_at.is_(None) | (VehicleReference.source_updated_at <= event.occurred_at))))
    committed(session, runtime.metrics.business["vehicle_events_consumed_total"])
    await try_prepare_inspection(session, vehicle_id)


def cdc_date(value):
    return date(1970, 1, 1) + timedelta(days=value) if isinstance(value, int) else date.fromisoformat(value)


def cdc_datetime(value):
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value / 1_000_000, UTC)
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


async def apply_warranty_cdc(session, event, runtime):
    envelope = event.data["envelope"]
    operation, source = envelope["op"], envelope["source"]
    row = envelope["before"] if operation == "d" else envelope["after"]
    vehicle_id, warranty_id = UUID(row["vehicle_id"]), UUID(row["id"])
    await lock_vehicle(session, vehicle_id)
    await session.execute(insert(VehicleReference).values(vehicle_id=vehicle_id, vehicle_seen=False, warranty_seen=False).on_conflict_do_nothing())
    values = dict(vehicle_id=vehicle_id, warranty_id=warranty_id, warranty_status=row["status"], warranty_type=row["warranty_type"],
                  start_date=cdc_date(row["start_date"]), end_date=cdc_date(row["end_date"]),
                  source_updated_at=cdc_datetime(row["updated_at"]), synced_at=utcnow(), source_lsn=int(source["lsn"]),
                  source_partition=event.data["partition"], source_offset=event.data["offset"], is_deleted=operation == "d")
    stmt = insert(VehicleWarrantyProjection).values(**values)
    # Keep deleted checkpoints: replaying an older snapshot must not resurrect a row.
    await session.execute(stmt.on_conflict_do_update(index_elements=["warranty_id"], set_=values,
        where=(VehicleWarrantyProjection.source_lsn < values["source_lsn"]) |
              ((VehicleWarrantyProjection.source_lsn == values["source_lsn"]) &
               (VehicleWarrantyProjection.source_partition == values["source_partition"]) &
               (VehicleWarrantyProjection.source_offset < values["source_offset"]))))
    await try_prepare_inspection(session, vehicle_id)
    log.info("warranty_cdc_projection_staged", extra={"fields": {"vehicle_id": str(vehicle_id),
             "warranty_id": str(warranty_id), "operation": operation, "source_lsn": values["source_lsn"]}})
    committed(session, runtime.metrics.cdc_events.labels(runtime.settings.service_name, operation))
    delay = max(0, (utcnow() - event.occurred_at).total_seconds())
    runtime.metrics.cdc_delay.labels(runtime.settings.service_name, "warranty-postgres-connector").observe(delay)


HANDLERS = {"vehicle.created": update_reference, "vehicle.updated": update_reference, "warranty.cdc": apply_warranty_cdc}
