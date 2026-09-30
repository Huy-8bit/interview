"""Lab-only test fixtures. PostgreSQL schemas isolate tests from running workers."""

from uuid import uuid4

import pytest_asyncio
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from platform_common.config import Settings
from platform_common.db import Base
from platform_common.runtime import Runtime


@pytest_asyncio.fixture
async def runtime():
    schema = "test_" + uuid4().hex
    settings = Settings(background_workers=False, service_name=schema, kafka_consumer_group=schema)
    runtime = Runtime(settings)
    admin_engine = runtime.engine
    async with admin_engine.begin() as connection:
        await connection.exec_driver_sql(f'CREATE SCHEMA "{schema}"')
    engine = create_async_engine(
        settings.database_url,
        pool_size=8,
        max_overflow=5,
        connect_args={"server_settings": {"search_path": schema}},
    )
    runtime.engine = engine
    runtime.sessions = async_sessionmaker(engine, expire_on_commit=False)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    try:
        yield runtime
    finally:
        await runtime.close()
        async with admin_engine.begin() as connection:
            await connection.exec_driver_sql(f'DROP SCHEMA "{schema}" CASCADE')
        await admin_engine.dispose()
