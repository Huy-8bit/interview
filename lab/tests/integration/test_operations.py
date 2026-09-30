import pytest
from sqlalchemy.ext.asyncio import create_async_engine

pytestmark = pytest.mark.integration


async def test_health_readiness_and_correlation(client):
    from uuid import uuid4

    correlation = str(uuid4())
    for service in ["vehicle", "warranty", "inspection", "repair"]:
        health = await client.request(
            service, "GET", "/health", headers={"X-Correlation-ID": correlation}
        )
        assert health.status_code == 200 and health.headers["X-Correlation-ID"] == correlation
        ready = await client.request(service, "GET", "/ready")
        assert ready.status_code == 200, ready.text
        assert set(ready.json()["checks"].values()) == {"ok"}


async def test_database_credentials_cannot_connect_to_other_services():
    import os

    from sqlalchemy.engine import make_url

    url = make_url(os.environ["VEHICLE_DATABASE_URL"]).set(database="warranty_db")
    engine = create_async_engine(url)
    try:
        with pytest.raises(Exception) as exc:
            async with engine.connect():
                pass
        assert "permission denied for database" in str(exc.value)
    finally:
        await engine.dispose()
