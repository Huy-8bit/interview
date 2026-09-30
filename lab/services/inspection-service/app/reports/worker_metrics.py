"""Prometheus metrics for Celery prefork workers.

Tasks run in child processes, so the worker sets PROMETHEUS_MULTIPROC_DIR and the
parent serves the aggregate of every child's files. Labels stay bounded: never a
task, inspection or vehicle ID.
"""
import os

from celery import signals
from prometheus_client import (
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    multiprocess,
    start_http_server,
)

from app.reports.celery_app import QUEUE, TASK_NAME, settings

SERVICE = os.getenv("SERVICE_NAME", "inspection-report-worker")
LABELS = ("service", "task_type", "queue")
BASE = (SERVICE, TASK_NAME, QUEUE)
BUCKETS = (0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 30, 60, 120, 300, 600)
OUTCOMES = ("generated", "duplicate", "retry", "permanent", "retries_exhausted")
FAILURES = ("permanent", "retries_exhausted")
RETRY_REASONS = ("timeout", "database", "dependency", "unexpected")

started = Counter("background_tasks_started_total", "Task executions started", LABELS)
completed = Counter("background_tasks_completed_total", "Task executions that finished their business effect", (*LABELS, "outcome"))
failed = Counter("background_tasks_failed_total", "Tasks sent to the dead-letter queue by the worker", (*LABELS, "reason"))
retried = Counter("background_tasks_retried_total", "Retries scheduled via delayed delivery", (*LABELS, "reason"))
redelivered = Counter("background_tasks_redelivered_total", "Deliveries RabbitMQ flagged as redelivered", LABELS)
duration = Histogram("background_task_duration_seconds", "Task execution time", (*LABELS, "outcome"), buckets=BUCKETS)
queue_wait = Histogram("background_task_queue_wait_seconds", "Dispatch-to-start time of first attempts", (*LABELS, "priority"), buckets=BUCKETS)
active = Gauge("background_tasks_active", "Tasks executing now", LABELS, multiprocess_mode="livesum")
ready = Gauge("background_worker_ready", "Worker consumer started", ("service",), multiprocess_mode="livemax")


def initialise():
    """Zero-valued series so rate() and dashboards show 0 instead of no data."""
    started.labels(*BASE)
    redelivered.labels(*BASE)
    active.labels(*BASE)
    for outcome in OUTCOMES:
        duration.labels(*BASE, outcome)
    for outcome in ("generated", "duplicate"):
        completed.labels(*BASE, outcome)
    for reason in FAILURES:
        failed.labels(*BASE, reason)
    for reason in RETRY_REASONS:
        retried.labels(*BASE, reason)
    for priority in ("high", "normal"):
        queue_wait.labels(*BASE, priority)


@signals.worker_init.connect
def serve(**_):
    registry = CollectorRegistry()
    multiprocess.MultiProcessCollector(registry)
    start_http_server(settings.report_metrics_port, registry=registry)
    initialise()


@signals.worker_ready.connect
def mark_ready(**_):
    ready.labels(SERVICE).set(1)


@signals.worker_shutting_down.connect
def mark_stopping(**_):
    ready.labels(SERVICE).set(0)


@signals.worker_process_shutdown.connect
def forget_child(pid=None, **_):
    multiprocess.mark_process_dead(pid or os.getpid())
