"""Celery worker entrypoint: celery -A app.reports.worker:celery_app worker ..."""
import os

from celery import signals

from app.reports import (
    tasks,  # noqa: F401 - registers inspection.generate_report
    worker_metrics,  # noqa: F401 - metrics server and lifecycle signals
)
from app.reports.celery_app import celery_app
from platform_common.logging import configure_logging

__all__ = ["celery_app"]


@signals.setup_logging.connect
def json_logs(**_):
    # Same JSON log format as the APIs; also stops Celery from hijacking the root logger.
    configure_logging(os.getenv("SERVICE_NAME", "inspection-report-worker"), os.getenv("LOG_LEVEL", "INFO"))
