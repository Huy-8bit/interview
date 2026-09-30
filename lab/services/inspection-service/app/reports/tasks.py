"""Inspection report task: at-least-once delivery, exactly-once business effect.

RabbitMQ may deliver a task more than once (worker crash before ACK, dispatcher
re-publish, DLQ replay). The effect is guarded at the commit point instead: the
row lock plus the GENERATED check means only one delivery stores the document and
enqueues inspection.report.generated; every other delivery ends as "duplicate".
"""
import logging
import os
import random
import time
from functools import cache
from uuid import UUID, uuid4

from celery.exceptions import Reject, SoftTimeLimitExceeded
from sqlalchemy import create_engine, select
from sqlalchemy.exc import DBAPIError
from sqlalchemy.exc import TimeoutError as PoolTimeout
from sqlalchemy.orm import sessionmaker

from app.models.inspection import (
    Inspection,
    InspectionReport,
    VehicleReference,
    VehicleWarrantyProjection,
)
from app.reports import rendering
from app.reports import worker_metrics as metrics
from app.reports.celery_app import TASK_NAME, celery_app, settings
from platform_common import context
from platform_common.config import Settings
from platform_common.db import utcnow
from platform_common.events import enqueue

log = logging.getLogger(__name__)


class PermanentReportError(Exception):
    """Input can never render (missing or incomplete inspection): do not retry."""


class TransientReportError(Exception):
    """A dependency failed; a later attempt may succeed."""


@cache
def app_settings():
    return Settings()


_sessions = {}


def sessions():
    """One small synchronous pool per worker process, created after fork."""
    pid = os.getpid()
    if pid not in _sessions:
        _sessions.clear()  # Never reuse sockets inherited from the parent process.
        config = app_settings()
        engine = create_engine(
            config.write_database_url.replace("+asyncpg", "+psycopg"),
            pool_size=1, max_overflow=1, pool_pre_ping=True, pool_timeout=config.db_pool_timeout,
            connect_args={"connect_timeout": 3, "options": f"-c statement_timeout={config.db_statement_timeout_ms} -c idle_in_transaction_session_timeout=30000"},
        )
        _sessions[pid] = sessionmaker(engine, expire_on_commit=False)
    return _sessions[pid]


def locked(session, inspection_id):
    return session.scalar(select(InspectionReport).where(InspectionReport.inspection_id == inspection_id).with_for_update())


def inject(fault):
    """Operator drill faults. Only broker publishers can set them; HTTP clients cannot."""
    if fault == "transient":
        raise TransientReportError("lab fault: renderer dependency timed out")
    if fault == "hang":
        time.sleep(settings.report_time_limit * 2)  # Interrupted by the soft time limit.
    if fault == "stuck":
        # Ignores the soft limit like a blocked C call; only the hard limit ends it.
        deadline = time.monotonic() + settings.report_time_limit * 2
        while time.monotonic() < deadline:
            try:
                time.sleep(1)
            except SoftTimeLimitExceeded:
                log.warning("report_task_ignoring_soft_time_limit")
    if fault and fault.startswith("slow:"):
        time.sleep(float(fault.split(":", 1)[1]))


def generate(session_factory, config, inspection_id, *, task_id, worker, render_cost_ms, fault=None):
    """Returns "generated" or "duplicate"; raises PermanentReportError or a retryable error."""
    if fault:
        inject(fault)
    try:
        inspection_id = UUID(str(inspection_id))
    except ValueError:
        raise PermanentReportError("invalid inspection_id") from None
    # Claim: short transaction, no lock held while rendering.
    with session_factory.begin() as session:
        report = locked(session, inspection_id)
        if report is None:
            raise PermanentReportError("no report request exists for this inspection")
        if report.status == "GENERATED":
            return "duplicate"
        inspection = session.get(Inspection, report.inspection_id)
        if inspection is None or inspection.status != "COMPLETED":
            raise PermanentReportError("inspection is not completed")
        vehicle = session.get(VehicleReference, inspection.vehicle_id)
        warranty = session.get(VehicleWarrantyProjection, inspection.warranty_id) if inspection.warranty_id else None
        report.status, report.attempts, report.worker, report.started_at = "PROCESSING", report.attempts + 1, worker, utcnow()
        data = rendering.snapshot(report, inspection, vehicle, warranty)
    document = rendering.render(data, render_cost_ms)
    # Commit point: exactly one delivery wins, even if duplicates rendered in parallel.
    with session_factory.begin() as session:
        report = locked(session, inspection_id)
        if report.status == "GENERATED":
            return "duplicate"
        report.status, report.document, report.sha256 = "GENERATED", document.pdf, document.sha256
        report.size_bytes, report.report_number, report.generated_at = len(document.pdf), document.report_number, utcnow()
        report.last_error = report.failed_at = None
        enqueue(session, config, "inspection.report.generated", data["vehicle_id"], {
            "report_id": str(report.id),
            "inspection_id": data["inspection_id"],
            "vehicle_id": data["vehicle_id"],
            "kind": report.kind,
            "result": data["result"],
            "report_number": document.report_number,
            "sha256": document.sha256,
            "size_bytes": len(document.pdf),
            "generated_at": report.generated_at.isoformat(),
        })
    return "generated"


def record_failure(session_factory, inspection_id, error, *, final):
    """Best effort: the DB may be the very dependency that failed."""
    try:
        with session_factory.begin() as session:
            report = locked(session, UUID(str(inspection_id)))
            if report is None or report.status == "GENERATED":
                return
            report.status = "FAILED" if final else "RETRY_SCHEDULED"
            report.last_error = error[:2000]
            if final:
                report.failed_at = utcnow()
    except Exception as exc:  # noqa: BLE001 - never mask the original failure
        log.warning("report_failure_not_recorded", extra={"fields": {"error_type": type(exc).__name__}})


def classify(exc):
    if isinstance(exc, SoftTimeLimitExceeded):
        return "timeout"
    if isinstance(exc, (DBAPIError, PoolTimeout)):
        return "database"
    if isinstance(exc, (TransientReportError, OSError)):
        return "dependency"
    return "unexpected"


def backoff(retries):
    """Exponential with +/-20% jitter so a shared outage does not retry in lockstep."""
    delay = min(settings.report_retry_max_seconds, settings.report_retry_base_seconds * 2 ** retries)
    return max(1, round(delay * random.uniform(0.8, 1.2)))


@celery_app.task(bind=True, name=TASK_NAME, max_retries=settings.report_max_retries)
def generate_report(self, inspection_id, correlation_id=None, submitted_at=None, fault=None):
    request = self.request
    delivery = request.delivery_info or {}
    fields = {"inspection_id": inspection_id, "task_id": request.id, "attempt": request.retries + 1, "worker": request.hostname}
    token = context.correlation_id.set(correlation_id or str(uuid4()))
    started, outcome = time.monotonic(), "unexpected"
    metrics.started.labels(*metrics.BASE).inc()
    metrics.active.labels(*metrics.BASE).inc()
    if delivery.get("redelivered"):
        metrics.redelivered.labels(*metrics.BASE).inc()
    if request.retries == 0 and submitted_at:
        priority = "high" if (delivery.get("priority") or 0) > 4 else "normal"
        metrics.queue_wait.labels(*metrics.BASE, priority).observe(max(0.0, time.time() - submitted_at))
    try:
        outcome = generate(sessions(), app_settings(), inspection_id, task_id=request.id, worker=request.hostname,
                           render_cost_ms=settings.report_render_cost_ms, fault=fault)
        metrics.completed.labels(*metrics.BASE, outcome).inc()
        log.info("report_task_" + outcome, extra={"fields": fields})
        return outcome
    except PermanentReportError as exc:
        outcome = "permanent"
        record_failure(sessions(), inspection_id, f"permanent: {exc}", final=True)
        metrics.failed.labels(*metrics.BASE, outcome).inc()
        log.error("report_task_dead_lettered", extra={"fields": {**fields, "reason": outcome, "error": str(exc)}})
        # requeue=False: the quorum queue dead-letters it to inspection.report.dlq.
        raise Reject(str(exc), requeue=False) from exc
    except Exception as exc:
        reason, error = classify(exc), f"{type(exc).__name__}: {exc}"
        if request.retries >= self.max_retries:
            outcome = "retries_exhausted"
            record_failure(sessions(), inspection_id, f"retries exhausted ({reason}): {error}", final=True)
            metrics.failed.labels(*metrics.BASE, outcome).inc()
            log.error("report_task_dead_lettered", extra={"fields": {**fields, "reason": outcome, "error": error}})
            raise  # acks_on_failure_or_timeout=False -> basic.reject(requeue=False) -> DLQ
        outcome, countdown = "retry", backoff(request.retries)
        record_failure(sessions(), inspection_id, f"attempt {request.retries + 1} ({reason}): {error}", final=False)
        metrics.retried.labels(*metrics.BASE, reason).inc()
        log.warning("report_task_retry_scheduled", extra={"fields": {**fields, "reason": reason, "countdown": countdown, "error": error}})
        # A new message with retries+1 goes through celery_delayed_* TTL queues and
        # comes back to the work queue; this delivery is ACKed afterwards.
        raise self.retry(exc=exc, countdown=countdown) from exc
    finally:
        metrics.active.labels(*metrics.BASE).dec()
        metrics.duration.labels(*metrics.BASE, outcome).observe(time.monotonic() - started)
        context.correlation_id.reset(token)
