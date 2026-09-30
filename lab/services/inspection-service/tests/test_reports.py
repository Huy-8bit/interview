import asyncio
import itertools
from concurrent.futures import ThreadPoolExecutor
from uuid import UUID, uuid4

import pytest
from celery.exceptions import Reject
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker
from test_inspection import cdc_event

from app.messaging.handlers import apply_warranty_cdc, update_reference
from app.models.inspection import Inspection, InspectionReport
from app.reports import rendering, tasks
from app.reports import worker_metrics as metrics
from app.reports.dispatcher import ApiReportMetrics, dispatch_once
from app.reports.settings import ReportSettings
from app.schemas.inspection import InspectionComplete, InspectionCreate
from app.services.inspections import InspectionService
from platform_common.consumer import process_event
from platform_common.db import utcnow
from platform_common.events import Event
from platform_common.models import OutboxEvent

OFFSETS = itertools.count(100)


def sync_sessions(runtime):
    """The worker's synchronous psycopg access, pointed at the test schema."""
    engine = create_engine(runtime.settings.write_database_url.replace("+asyncpg", "+psycopg"),
                           connect_args={"options": f"-csearch_path={runtime.settings.service_name}"})
    return sessionmaker(engine, expire_on_commit=False)


async def prepared_vehicle(runtime):
    """Both inputs arrived; a unique CDC offset per vehicle avoids ledger deduplication."""
    vehicle_id, offset = uuid4(), next(OFFSETS)
    await process_event(runtime, cdc_event(vehicle_id, lsn=offset, offset=offset), apply_warranty_cdc)
    await process_event(runtime, Event(event_id=uuid4(), event_type="vehicle.created", occurred_at=utcnow(), producer="test",
                                       correlation_id=str(uuid4()), data={"id": str(vehicle_id), "vin": "TRF0000000000001"}), update_reference)
    return vehicle_id


async def completed(runtime, result="FAIL"):
    service = InspectionService(runtime)
    created = await service.create(InspectionCreate(vehicle_id=await prepared_vehicle(runtime)), str(uuid4()))
    body = InspectionComplete(result=result, failure_reason="brake issue" if result == "FAIL" else None)
    await service.complete(UUID(created["id"]), body)
    return UUID(created["id"])


async def test_completion_creates_one_prioritised_report_request(runtime):
    failed, passed = await completed(runtime, "FAIL"), await completed(runtime, "PASS")
    service = InspectionService(runtime)
    await service.complete(failed, InspectionComplete(result="FAIL", failure_reason="brake issue"))  # idempotent repeat
    async with runtime.sessions() as session:
        rows = {row.inspection_id: row for row in await session.scalars(select(InspectionReport))}
    assert len(rows) == 2
    assert (rows[failed].kind, rows[failed].priority, rows[failed].status) == ("DEFECT_REPORT", 9, "PENDING")
    assert (rows[passed].kind, rows[passed].priority) == ("CERTIFICATE", 0)
    assert (await service.report(failed))["priority"] == "HIGH"


async def test_dispatcher_marks_only_confirmed_rows_and_backs_off(runtime):
    passed, failed, other = [await completed(runtime, r) for r in ("PASS", "FAIL", "PASS")]
    metrics_ = ApiReportMetrics(runtime.metrics.registry, runtime.settings.service_name)
    calls = []

    def one_then_broker_down(jobs):
        calls.append(jobs)
        return 1, "ConnectionRefusedError: broker down"

    published, error = await dispatch_once(runtime, ReportSettings(), metrics_, one_then_broker_down)
    assert published == 1 and error
    assert calls[0][0].priority == 9  # Defect report first.
    async with runtime.sessions() as session:
        rows = {row.inspection_id: row for row in await session.scalars(select(InspectionReport))}
    assert rows[failed].status == "QUEUED" and rows[failed].queued_at
    first_waiting = rows[passed] if rows[passed].dispatch_attempts else rows[other]
    assert first_waiting.status == "PENDING" and first_waiting.last_error.startswith("dispatch:")
    assert first_waiting.next_dispatch_at > utcnow()
    untouched = rows[other] if first_waiting is rows[passed] else rows[passed]
    assert untouched.dispatch_attempts == 0 and untouched.last_error is None

    published, error = await dispatch_once(runtime, ReportSettings(), metrics_, lambda jobs: (len(jobs), None))
    assert (published, error) == (1, None)  # The backed-off row waits for its next_dispatch_at.


async def test_duplicate_deliveries_store_one_document_and_one_event(runtime):
    inspection_id = await completed(runtime)
    factory = sync_sessions(runtime)

    def deliver(name):
        return tasks.generate(factory, runtime.settings, str(inspection_id), task_id="same-task", worker=name, render_cost_ms=200)

    with ThreadPoolExecutor(2) as pool:  # Two workers received the same message.
        outcomes = sorted(pool.map(deliver, ["worker-a", "worker-b"]))
    assert outcomes == ["duplicate", "generated"]  # Both may render; only one commits.
    assert deliver("redelivery") == "duplicate"
    async with runtime.sessions() as session:
        report = await session.scalar(select(InspectionReport))
        events = await session.scalar(select(func.count()).select_from(OutboxEvent).where(OutboxEvent.event_type == "inspection.report.generated"))
        inspection = await session.get(Inspection, inspection_id)
    assert report.status == "GENERATED" and report.sha256 and report.size_bytes > 0
    assert events == 1
    assert report.report_number == rendering.report_number({"completed_at": inspection.completed_at.isoformat(), "inspection_id": str(inspection_id)})


async def test_invalid_input_is_permanent_and_rejected_without_retry(runtime, monkeypatch):
    factory = sync_sessions(runtime)
    for inspection_id in (str(uuid4()), "not-a-uuid"):
        with pytest.raises(tasks.PermanentReportError):
            tasks.generate(factory, runtime.settings, inspection_id, task_id="t", worker="w", render_cost_ms=0)
    monkeypatch.setattr(tasks, "sessions", lambda: factory)
    before = metrics.retried.labels(*metrics.BASE, "dependency")._value.get()
    result = tasks.generate_report.apply(kwargs={"inspection_id": str(uuid4())})
    assert result.state == "REJECTED" and isinstance(result.result, Reject)  # requeue=False -> DLX
    assert metrics.retried.labels(*metrics.BASE, "dependency")._value.get() == before


async def test_transient_failure_spends_retry_budget_then_fails(runtime, monkeypatch):
    inspection_id = await completed(runtime)
    factory = sync_sessions(runtime)
    monkeypatch.setattr(tasks, "sessions", lambda: factory)
    retried = metrics.retried.labels(*metrics.BASE, "dependency")._value.get()
    exhausted = metrics.failed.labels(*metrics.BASE, "retries_exhausted")._value.get()
    # Eager mode runs retries inline; on RabbitMQ each one goes through celery_delayed_*.
    result = await asyncio.to_thread(tasks.generate_report.apply, kwargs={"inspection_id": str(inspection_id), "fault": "transient"})
    assert result.state == "FAILURE" and isinstance(result.result, tasks.TransientReportError)
    assert metrics.retried.labels(*metrics.BASE, "dependency")._value.get() - retried == tasks.settings.report_max_retries
    assert metrics.failed.labels(*metrics.BASE, "retries_exhausted")._value.get() - exhausted == 1
    async with runtime.sessions() as session:
        report = await session.scalar(select(InspectionReport))
    assert report.status == "FAILED" and "retries exhausted" in report.last_error and report.failed_at


def test_rendering_is_deterministic_and_backoff_is_bounded():
    data = {"inspection_id": str(uuid4()), "vehicle_id": str(uuid4()), "kind": "DEFECT_REPORT", "result": "FAIL",
            "inspection_type": "PERIODIC", "failure_reason": "brake (rear)", "completed_at": "2026-09-30T00:00:00+00:00",
            "vin": "TRF123", "vehicle": "VinFast VF 8 2024", "owner_name": "Le Chi", "warranty_id": None, "warranty": "none on record"}
    first, second = rendering.render(data, 0), rendering.render(data, 0)
    assert first == second and first.pdf.startswith(b"%PDF-1.4") and b"brake \\(rear\\)" in first.pdf
    delays = [tasks.backoff(retry) for retry in range(10) for _ in range(20)]
    assert min(delays) >= 1 and max(delays) <= tasks.settings.report_retry_max_seconds * 1.2
    assert tasks.backoff(0) < tasks.backoff(4)
