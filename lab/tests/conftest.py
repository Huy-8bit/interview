import os

import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from platform_common.redis import cluster_client
from scripts.lab_client import LabClient


@pytest_asyncio.fixture
async def client():
    client = LabClient()
    try:
        yield client
    finally:
        await client.close()


@pytest_asyncio.fixture
async def redis_client():
    client = cluster_client(os.environ["REDIS_CLUSTER_NODES"])
    try:
        yield client
    finally:
        await client.aclose()


@pytest_asyncio.fixture
async def db():
    engines = {}

    async def query(service, sql, **params):
        if service not in engines:
            engines[service] = create_async_engine(os.environ[service.upper() + "_DATABASE_URL"])
        async with engines[service].connect() as connection:
            result = await connection.execute(text(sql), params)
            return result.mappings().all()

    try:
        yield query
    finally:
        for engine in engines.values():
            await engine.dispose()
