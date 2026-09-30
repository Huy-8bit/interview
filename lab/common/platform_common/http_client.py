"""Shared observation of real outbound HTTP attempts; callers own retry policy."""
import time
from uuid import uuid4

from platform_common import context


async def request(runtime, target, method, path, template, **kwargs):
    started, status = time.perf_counter(), 'network_error'
    supplied = kwargs.pop('headers', {})
    try:
        response = await runtime.http.request(method, runtime.settings.warranty_service_url + path, headers={
            'X-Correlation-ID': context.correlation_id.get() or str(uuid4()),
            'X-Request-ID': str(uuid4()), **supplied,
        }, **kwargs)
        status = str(response.status_code)
        return response
    finally:
        metrics = runtime.metrics
        labels = (metrics.service, target, method, template, status)
        metrics.client_requests.labels(*labels).inc()
        metrics.client_duration.labels(*labels[:-1]).observe(time.perf_counter() - started)
        if status == 'network_error' or int(status) >= 400:
            metrics.client_errors.labels(*labels).inc()
