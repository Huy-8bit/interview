import asyncio
from uuid import uuid4

import httpx
import pytest
from sqlalchemy import func, select

from app.infrastructure.warranty_client import check_coverage
from app.messaging.handlers import inspection_failed
from app.models.repair import Notification, RepairRequest
from app.schemas.repair import RepairCreate
from app.services.repairs import RepairService
from platform_common.consumer import process_event
from platform_common.db import utcnow
from platform_common.errors import TransientError
from platform_common.events import Event
from platform_common.models import OutboxEvent, ProcessedEvent


async def http_transport(runtime, handler):
    await runtime.http.aclose()
    runtime.http = httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_duplicate_consumer_and_api_create_share_natural_key(runtime):
    vehicle_id, inspection_id = uuid4(), uuid4()
    await http_transport(
        runtime,
        lambda request: httpx.Response(
            200,
            json={
                "vehicle_id": str(vehicle_id),
                "covered": True,
                "warranty_id": str(uuid4()),
                "checked_at": utcnow().isoformat(),
            },
        ),
    )
    event = Event(
        event_id=uuid4(),
        event_type="inspection.failed",
        occurred_at=utcnow(),
        producer="test",
        correlation_id=str(uuid4()),
        data={
            "vehicle_id": str(vehicle_id),
            "inspection_id": str(inspection_id),
            "failure_reason": "leak",
            "occurred_at": utcnow().isoformat(),
        },
    )
    results = await asyncio.gather(
        *(process_event(runtime, event, inspection_failed) for _ in range(4))
    )
    assert sum(results) == 1
    body = RepairCreate(vehicle_id=vehicle_id, inspection_id=inspection_id, description="leak")
    service = RepairService(runtime)
    key = str(uuid4())
    first = await service.create(body, key)
    assert await service.create(body, key) == first
    async with runtime.sessions() as session:
        for model in (RepairRequest, Notification, OutboxEvent):
            assert await session.scalar(select(func.count()).select_from(model)) == 1
        assert (await session.scalar(select(RepairRequest))).warranty_covered is True


async def test_unavailable_warranty_never_becomes_uncovered_and_marker_rolls_back(runtime):
    calls = []

    def unavailable(request):
        calls.append(request)
        raise httpx.ReadTimeout("simulated timeout", request=request)

    await http_transport(runtime, unavailable)
    runtime.settings.http_retries = 1
    with pytest.raises(TransientError):
        await check_coverage(runtime, uuid4())
    assert len(calls) == 2
    event = Event(
        event_id=uuid4(),
        event_type="inspection.failed",
        occurred_at=utcnow(),
        producer="test",
        correlation_id=str(uuid4()),
        data={
            "vehicle_id": str(uuid4()),
            "inspection_id": str(uuid4()),
            "failure_reason": "leak",
            "occurred_at": utcnow().isoformat(),
        },
    )
    with pytest.raises(TransientError):
        await process_event(runtime, event, inspection_failed)
    async with runtime.sessions() as session:
        assert await session.scalar(select(func.count()).select_from(RepairRequest)) == 0
        assert await session.scalar(select(func.count()).select_from(ProcessedEvent)) == 0


async def test_defect_report_is_attached_once_and_certificates_are_ignored(runtime):
    from app.messaging.handlers import inspection_report_generated

    vehicle_id, inspection_id = uuid4(), uuid4()
    async with runtime.sessions.begin() as session:
        session.add(RepairRequest(vehicle_id=vehicle_id, inspection_id=inspection_id, warranty_covered=True, description="brake issue"))

    def generated(inspection, result):
        return Event(event_id=uuid4(), event_type="inspection.report.generated", occurred_at=utcnow(), producer="test",
                     correlation_id=str(uuid4()), data={
                         "report_id": str(uuid4()), "inspection_id": str(inspection), "vehicle_id": str(vehicle_id),
                         "kind": "DEFECT_REPORT" if result == "FAIL" else "CERTIFICATE", "result": result,
                         "report_number": "IR-20260930-ABCDEF12", "sha256": "a" * 64, "size_bytes": 1000,
                         "generated_at": utcnow().isoformat()})

    event = generated(inspection_id, "FAIL")
    assert await process_event(runtime, event, inspection_report_generated)
    assert not await process_event(runtime, event, inspection_report_generated)  # Kafka redelivery.
    assert await process_event(runtime, generated(uuid4(), "PASS"), inspection_report_generated)
    assert await process_event(runtime, generated(uuid4(), "FAIL"), inspection_report_generated)  # No repair: no-op.
    async with runtime.sessions() as session:
        repair = await session.scalar(select(RepairRequest))
        assert (repair.defect_report_number, repair.defect_report_sha256) == ("IR-20260930-ABCDEF12", "a" * 64)
        assert await session.scalar(select(func.count()).select_from(RepairRequest)) == 1
