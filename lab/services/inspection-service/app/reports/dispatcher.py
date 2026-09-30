"""Publish PENDING report rows to RabbitMQ from the Inspection API process.

The completion transaction only inserts a row; it never talks to RabbitMQ. This
loop publishes the row with publisher confirms and then marks it QUEUED. A crash
after the confirm but before the commit re-publishes the same task_id later; the
task treats that second delivery as a duplicate. A RabbitMQ outage therefore
delays reports but never fails POST /inspections/{id}/complete.
"""
import asyncio
import logging
import time
from dataclasses import dataclass
from datetime import timedelta

from prometheus_client import Counter, Gauge
from sqlalchemy import func, select

from app.models.inspection import InspectionReport
from app.reports.settings import ReportSettings
from platform_common.db import utcnow
from platform_common.metrics import committed
from platform_common.outbox import backoff

log = logging.getLogger(__name__)
# GENERATED is excluded: it grows forever; background_tasks_completed_total covers it.
OPEN_STATUSES = ("PENDING", "QUEUED", "PROCESSING", "RETRY_SCHEDULED", "FAILED")
TASK_TYPE, QUEUE = "inspection.generate_report", "inspection.report.generate"
RETRY_POLICY = {"max_retries": 1, "interval_start": 0, "interval_step": 0.5, "interval_max": 0.5}


class ApiReportMetrics:
    def __init__(self, registry, service):
        labels = (service, TASK_TYPE, QUEUE)
        self.submitted = Counter("background_tasks_submitted_total", "Tasks confirmed by RabbitMQ", ("service", "task_type", "queue"), registry=registry).labels(*labels)
        self.dispatch_failed = Counter("background_task_dispatch_failures_total", "Publish attempts RabbitMQ did not confirm", ("service", "task_type", "queue"), registry=registry).labels(*labels)
        reports = Gauge("inspection_reports_open", "Report rows not yet GENERATED, by status", ("service", "status"), registry=registry)
        self.reports = {status: reports.labels(service, status) for status in OPEN_STATUSES}


def api_metrics(runtime):
    if getattr(runtime, "report_metrics", None) is None:
        runtime.report_metrics = ApiReportMetrics(runtime.metrics.registry, runtime.settings.service_name)
    return runtime.report_metrics


@dataclass(frozen=True)
class Job:
    task_id: str
    priority: int
    kwargs: dict


def publish(jobs):
    """Blocking kombu publish; returns (published, error) and stops at the first failure."""
    from app.reports.celery_app import TASK_NAME, celery_app

    published = 0
    try:
        with celery_app.producer_or_acquire() as producer:
            for job in jobs:
                celery_app.send_task(TASK_NAME, kwargs={**job.kwargs, "submitted_at": time.time()}, task_id=job.task_id,
                                     priority=job.priority, producer=producer, retry=True, retry_policy=RETRY_POLICY,
                                     confirm_timeout=5)
                published += 1
    except Exception as exc:  # noqa: BLE001 - any broker error leaves the rows PENDING
        return published, f"{type(exc).__name__}: {exc}"[:500]
    return published, None


async def dispatch_once(runtime, settings, metrics, publisher=publish):
    async with runtime.sessions.begin() as session:
        rows = (await session.scalars(
            select(InspectionReport)
            .where(InspectionReport.status == "PENDING", InspectionReport.next_dispatch_at <= utcnow())
            .order_by(InspectionReport.priority.desc(), InspectionReport.created_at)
            .limit(settings.report_dispatch_batch)
            .with_for_update(skip_locked=True)
        )).all()
        if not rows:
            return 0, None
        jobs = [Job(str(row.task_id), row.priority, {"inspection_id": str(row.inspection_id), "correlation_id": row.correlation_id}) for row in rows]
        published, error = await asyncio.to_thread(publisher, jobs)
        now = utcnow()
        for row in rows[:published]:
            row.status, row.queued_at, row.last_error = "QUEUED", now, None
            row.dispatch_attempts += 1
        if error:
            failed = rows[published]
            failed.dispatch_attempts += 1
            failed.last_error = f"dispatch: {error}"
            failed.next_dispatch_at = now + timedelta(seconds=backoff(failed.dispatch_attempts - 1, 1, settings.report_dispatch_retry_max_seconds))
            metrics.dispatch_failed.inc()
        committed(session, metrics.submitted, published)
    return published, error


async def report_dispatch_loop(runtime):
    settings, metrics, failures = ReportSettings(), api_metrics(runtime), 0
    while True:
        try:
            published, error = await dispatch_once(runtime, settings, metrics)
            if error:
                failures += 1
                log.warning("report_dispatch_failed", extra={"fields": {"published": published, "error": error}})
                await asyncio.sleep(backoff(failures - 1, 1, settings.report_dispatch_retry_max_seconds))
                continue
            failures = 0
            if published:
                log.info("report_tasks_dispatched", extra={"fields": {"count": published}})
            else:
                await asyncio.sleep(settings.report_dispatch_interval)
        except Exception:
            log.exception("report_dispatch_iteration_failed")
            await asyncio.sleep(settings.report_dispatch_interval)


async def report_status_loop(runtime):
    """Report rows by status; with API replicas use max by(status) in PromQL."""
    metrics = api_metrics(runtime)
    while True:
        try:
            async with asyncio.timeout(2):
                async with runtime.sessions() as session:
                    counts = dict((await session.execute(
                        select(InspectionReport.status, func.count())
                        .where(InspectionReport.status != "GENERATED").group_by(InspectionReport.status)
                    )).all())
            for status, gauge in metrics.reports.items():
                gauge.set(counts.get(status, 0))
        except Exception:
            log.warning("report_status_collection_failed")
        await asyncio.sleep(5)
