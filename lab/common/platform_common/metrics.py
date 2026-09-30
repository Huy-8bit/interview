"""Process metrics with bounded labels. Business counters advance only after DB commit."""
import asyncio
import logging
import time

from prometheus_client import CollectorRegistry, Counter, Gauge, Histogram, ProcessCollector
from sqlalchemy import event, func, select
from sqlalchemy.orm import Session

from platform_common.models import OutboxEvent

log = logging.getLogger(__name__)
BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30)
BUSINESS = (
    "vehicles_created_total", "vehicle_cache_hit_total", "vehicle_cache_miss_total",
    "warranties_created_total", "warranty_rest_requests_total", "inspections_created_total",
    "inspections_passed_total", "inspections_failed_total", "repairs_created_total",
    "warranty_coverage_check_total", "vehicle_events_consumed_total",
)


class Metrics:
    def __init__(self, service):
        self.service = service
        self.registry = CollectorRegistry()
        ProcessCollector(registry=self.registry)
        def counter(name, labels=()):
            return Counter(name, name.replace('_', ' '), ('service', *labels), registry=self.registry)
        def gauge(name, labels=()):
            return Gauge(name, name.replace('_', ' '), ('service', *labels), registry=self.registry)
        def histogram(name, labels=()):
            return Histogram(name, name.replace('_', ' '), ('service', *labels), buckets=BUCKETS, registry=self.registry)
        self.http_requests = counter('http_requests_total', ('method', 'route', 'status_code'))
        self.http_errors = counter('http_request_errors_total', ('method', 'route', 'status_code'))
        self.http_duration = histogram('http_request_duration_seconds', ('method', 'route'))
        self.http_active = gauge('http_requests_in_progress', ('method',))
        self.business = {name: counter(name).labels(service) for name in BUSINESS}
        self.events = {kind: counter(f'events_{kind}_total', ('event_type', 'topic')) for kind in ('consumed', 'processed', 'failed', 'duplicate', 'retried', 'dlq')}
        self.event_duration = histogram('event_processing_duration_seconds', ('event_type', 'topic'))
        self.cdc_events = counter('warranty_cdc_events_total', ('operation',))
        self.cdc_delay = histogram('cdc_source_to_consumer_seconds', ('connector',))
        self.outbox_pending = gauge('outbox_pending_events').labels(service)
        self.outbox_published = counter('outbox_published_total').labels(service)
        self.outbox_failed = counter('outbox_publish_failed_total').labels(service)
        self.outbox_duration = histogram('outbox_publish_duration_seconds').labels(service)
        self.db_success = gauge('metrics_db_collection_success').labels(service)
        self.db_collected_at = gauge('metrics_db_collection_timestamp_seconds').labels(service)
        self.db_pool = {name: gauge(f'db_pool_{name}', ('role',)) for name in ('size', 'checked_out', 'idle_connections', 'overflow', 'capacity')}
        self.pool_errors = counter('db_pool_timeouts_total').labels(service)
        self.client_requests = counter('service_client_requests_total', ('target_service', 'method', 'endpoint', 'status_code'))
        self.client_errors = counter('service_client_errors_total', ('target_service', 'method', 'endpoint', 'status_code'))
        self.client_duration = histogram('service_client_request_duration_seconds', ('target_service', 'method', 'endpoint'))
        self.rest_pending = gauge('warranty_provision_pending_requests').labels(service)
        self.rest_failures = counter('warranty_provision_failures_total').labels(service)

    def pools(self, runtime):
        for role, engine in (('primary', runtime.engine), ('replica', runtime.read_engine)):
            pool = engine.sync_engine.pool
            values = dict(size=pool.size(), checked_out=pool.checkedout(), idle_connections=pool.checkedin(), overflow=max(0, pool.overflow()), capacity=runtime.settings.db_pool_size + runtime.settings.db_max_overflow)
            for key, value in values.items():
                self.db_pool[key].labels(self.service, role).set(value)


def committed(session, metric, amount=1):
    session.sync_session.info.setdefault('metric_commits', []).append((metric, amount))


@event.listens_for(Session, 'after_commit')
def after_commit(session):
    for metric, amount in session.info.pop('metric_commits', []):
        metric.inc(amount)


@event.listens_for(Session, 'after_rollback')
def after_rollback(session):
    session.info.pop('metric_commits', None)


async def metrics_loop(runtime):
    while True:
        try:
            async with asyncio.timeout(2):
                async with runtime.sessions() as session:
                    count = await session.scalar(select(func.count()).select_from(OutboxEvent).where(OutboxEvent.status == 'PENDING'))
            runtime.metrics.outbox_pending.set(count)
            runtime.metrics.db_success.set(1)
            runtime.metrics.db_collected_at.set(time.time())
        except Exception:
            runtime.metrics.db_success.set(0)
            log.warning('metrics_database_collection_failed')
        await asyncio.sleep(5)


class HTTPMetricsMiddleware:
    """Pure ASGI middleware measures the complete response, including exceptions."""
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or scope.get('path') in ('/metrics', '/health', '/ready'):
            return await self.app(scope, receive, send)
        runtime = getattr(scope['app'].state, 'runtime', None)
        if runtime is None:
            return await self.app(scope, receive, send)
        metrics = runtime.metrics
        method = scope['method'] if scope['method'] in ('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS') else 'OTHER'
        started, status = time.perf_counter(), 500
        active = metrics.http_active.labels(metrics.service, method)
        active.inc()
        async def measured_send(message):
            nonlocal status
            if message['type'] == 'http.response.start':
                status = message['status']
            await send(message)
        try:
            await self.app(scope, receive, measured_send)
        finally:
            active.dec()
            route = getattr(scope.get('route'), 'path', '__unmatched__')
            labels = (metrics.service, method, route, str(status))
            metrics.http_requests.labels(*labels).inc()
            metrics.http_duration.labels(*labels[:3]).observe(time.perf_counter() - started)
            if status >= 400:
                metrics.http_errors.labels(*labels).inc()
