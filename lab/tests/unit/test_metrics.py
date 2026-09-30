from types import SimpleNamespace
from uuid import uuid4

import httpx
from fastapi import FastAPI
from prometheus_client import generate_latest

from platform_common.metrics import HTTPMetricsMiddleware, Metrics


async def test_http_uses_route_template_tracks_status_and_balances_active_requests():
    app = FastAPI()
    metrics = Metrics('test-service')
    app.state.runtime = SimpleNamespace(metrics=metrics)
    app.add_middleware(HTTPMetricsMiddleware)
    @app.get('/vehicles/{vehicle_id}')
    async def get_vehicle(vehicle_id: str):
        return {'id': vehicle_id}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://test') as client:
        for _ in range(5):
            assert (await client.get('/vehicles/'+str(uuid4()))).status_code == 200
        assert (await client.get('/absent/'+str(uuid4()))).status_code == 404
    text = generate_latest(metrics.registry).decode()
    assert 'route="/vehicles/{vehicle_id}"' in text
    assert 'route="__unmatched__"' in text
    assert metrics.http_requests.labels('test-service','GET','/vehicles/{vehicle_id}','200')._value.get() == 5
    assert metrics.http_errors.labels('test-service','GET','__unmatched__','404')._value.get() == 1
    assert metrics.http_active.labels('test-service','GET')._value.get() == 0
    assert '/absent/' not in text
