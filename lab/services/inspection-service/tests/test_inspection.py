import asyncio
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select

from app.messaging.handlers import apply_warranty_cdc, update_reference
from app.models.inspection import Inspection, VehicleReference
from app.schemas.inspection import InspectionComplete, InspectionCreate
from app.services.inspections import InspectionService
from platform_common.consumer import process_event
from platform_common.db import utcnow
from platform_common.errors import DomainError
from platform_common.events import Event
from platform_common.models import OutboxEvent


async def reference(runtime):
    vehicle_id = uuid4()
    # Deliberately reversed: a genuine decoded CDC envelope precedes domain event.
    await process_event(runtime, cdc_event(vehicle_id), apply_warranty_cdc)
    event = Event(event_id=uuid4(), event_type="vehicle.created", occurred_at=utcnow(), producer="test",
                  correlation_id=str(uuid4()), data={"id": str(vehicle_id)})
    await process_event(runtime, event, update_reference)
    async with runtime.sessions() as session:
        row = await session.get(VehicleReference, vehicle_id)
        assert row.vehicle_seen and row.warranty_seen
    return vehicle_id


async def test_concurrent_idempotency_and_redis_eviction(runtime):
    service = InspectionService(runtime)
    body = InspectionCreate(vehicle_id=await reference(runtime))
    key = str(uuid4())
    results = await asyncio.gather(*(service.create(body, key) for _ in range(6)))
    assert len({row["id"] for row in results}) == 1
    keys = [key async for key in runtime.redis.scan_iter(f"idem:{runtime.settings.service_name}:*")]
    if keys:
        for cache_key in keys:
            await runtime.redis.delete(cache_key)  # Different slots: no cross-slot multi-key DEL.
    assert await service.create(body, key) == results[0]
    with pytest.raises(DomainError) as error:
        await service.create(body.model_copy(update={"notes": "changed"}), key)
    assert error.value.status == 409
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(Inspection)) == 1


async def test_completion_is_atomic_and_repeat_does_not_emit_again(runtime):
    service = InspectionService(runtime)
    created = await service.create(
        InspectionCreate(vehicle_id=await reference(runtime)), str(uuid4())
    )
    identity = UUID(created["id"])
    complete = InspectionComplete(result="FAIL", failure_reason="brake defect")
    first = await service.complete(identity, complete)
    assert await service.complete(identity, complete) == first
    with pytest.raises(DomainError):
        await service.complete(identity, InspectionComplete(result="PASS"))
    async with runtime.sessions() as session:
        rows = (await session.scalars(select(OutboxEvent))).all()
        assert len(rows) == 1 and rows[0].event_type == "inspection.failed"
        assert set(rows[0].payload["data"]) == {
            "inspection_id",
            "vehicle_id",
            "warranty_id",
            "failure_reason",
            "occurred_at",
        }


def cdc_event(vehicle_id, warranty_id=None, *, op="c", lsn=10, offset=1, status="ACTIVE"):
    import json
    from types import SimpleNamespace

    from app.messaging.cdc import CDC_TOPIC, decode
    row = dict(id=str(warranty_id or uuid4()), vehicle_id=str(vehicle_id), status=status, warranty_type="DEFAULT",
               start_date=20000, end_date=21000, updated_at=utcnow().isoformat())
    payload = dict(before=row if op == "d" else None, after=None if op == "d" else row, op=op,
                   source=dict(db="warranty_db", schema="public", table="warranties", lsn=lsn, ts_ms=int(utcnow().timestamp()*1000)), ts_ms=int(utcnow().timestamp()*1000))
    return decode(SimpleNamespace(topic=CDC_TOPIC, key=json.dumps({"id":row["id"]}).encode(), value=json.dumps(payload).encode(), partition=0, offset=offset))


@pytest.mark.parametrize("cdc_first", [False, True])
async def test_two_input_orders_stale_replay_updates_delete_and_snapshot(runtime, cdc_first):
    from app.models.inspection import VehicleWarrantyProjection
    vehicle_id, warranty_id = uuid4(), uuid4()
    domain = Event(event_id=uuid4(), event_type="vehicle.created", occurred_at=utcnow(), producer="test",
                   correlation_id=str(uuid4()), data={"id":str(vehicle_id)})
    cdc = cdc_event(vehicle_id, warranty_id, op="r")
    inputs = [(cdc, apply_warranty_cdc), (domain, update_reference)]
    if not cdc_first:
        inputs.reverse()
    for index, (event, handler) in enumerate(inputs):
        assert await process_event(runtime, event, handler)
        assert not await process_event(runtime, event, handler)
        async with runtime.sessions() as session:
            row = await session.get(VehicleReference, vehicle_id)
            assert row.workflow_status == ("READY" if index else "WAITING_VEHICLE" if cdc_first else "WAITING_WARRANTY")
    # Different Kafka records for the same source row: source LSN wins over Kafka offset.
    await process_event(runtime, cdc_event(vehicle_id, warranty_id, op="u", lsn=20, offset=2, status="EXPIRED"), apply_warranty_cdc)
    await process_event(runtime, cdc_event(vehicle_id, warranty_id, op="c", lsn=10, offset=3), apply_warranty_cdc)
    async with runtime.sessions() as session:
        assert (await session.get(VehicleWarrantyProjection,warranty_id)).warranty_status == "EXPIRED"
    await process_event(runtime, cdc_event(vehicle_id,warranty_id,op="d",lsn=30,offset=4), apply_warranty_cdc)
    await process_event(runtime, cdc_event(vehicle_id,warranty_id,op="r",lsn=10,offset=5), apply_warranty_cdc)
    async with runtime.sessions() as session:
        assert (await session.get(VehicleWarrantyProjection,warranty_id)).is_deleted
        assert (await session.get(VehicleReference,vehicle_id)).workflow_status == "WAITING_WARRANTY"


def test_cdc_null_tombstone_and_malformed_input():
    from types import SimpleNamespace

    from app.messaging.cdc import CDC_TOPIC, decode
    assert decode(SimpleNamespace(topic=CDC_TOPIC,value=None)) is None
    assert decode(SimpleNamespace(topic=CDC_TOPIC,value=b'{"schema":{},"payload":null}')) is None
    with pytest.raises(ValueError):
        decode(SimpleNamespace(topic=CDC_TOPIC,value=b'{"op":"x"}'))
