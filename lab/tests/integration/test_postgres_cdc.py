import os
from types import SimpleNamespace

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import create_async_engine

from scripts.cluster_verify import retry
from scripts.postgres_cdc_verify import main, verify

pytestmark = pytest.mark.integration


async def test_physical_replication_logical_slots_connectors_and_kafka():
    await verify()


async def test_replica_reader_cannot_write_and_eventual_read_bypasses_cache(client):
    engine = create_async_engine(os.environ["VEHICLE_READ_DATABASE_URL"])
    try:
        async with engine.connect() as connection:
            assert await connection.scalar(text("SELECT pg_is_in_recovery()")) is True
            with pytest.raises(DBAPIError):
                await connection.execute(text("UPDATE vehicles SET owner_name='forbidden' WHERE false"))
    finally:
        await engine.dispose()
    vehicle = await client.vehicle()

    async def read():
        r = await client.request("vehicle", "GET", f"/vehicles/{vehicle['id']}?consistency=eventual")
        assert r.status_code == 200
        assert r.headers["X-Read-Source"] == "replica" and r.headers["X-Cache"] == "BYPASS"
        return r.json()

    assert (await retry(read))["id"] == vehicle["id"]
    r = await client.request("vehicle", "GET", f"/vehicles/{vehicle['id']}")
    assert r.headers["X-Cache"] == "MISS" and r.headers["X-Read-Source"] == "primary"


async def test_real_wal_insert_update_delete_before_images_and_tombstone(tmp_path):
    await main(SimpleNamespace(mode="cdc", output=str(tmp_path / "cdc.json")))
