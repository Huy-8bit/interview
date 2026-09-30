import asyncio
import logging
from uuid import uuid4

import httpx
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.exc import TimeoutError as PoolTimeout

from platform_common.consumer import consumer_loop
from platform_common.db import database
from platform_common.kafka import KafkaPublisher
from platform_common.outbox import outbox_loop
from platform_common.redis import RedisSupport, cluster_client

log = logging.getLogger(__name__)


class Runtime:
    def __init__(self, settings):
        self.instance_id = str(uuid4())
        self.settings = settings
        self.engine, self.sessions = database(settings)
        self.read_engine, self.read_sessions = database(settings, read=True)
        self.redis = cluster_client(
            settings.redis_cluster_nodes,
            timeout=settings.redis_timeout,
            client_name=f"{settings.service_name}-{self.instance_id[:8]}",
        )
        self.cache = RedisSupport(self.redis, settings)
        self.publisher = KafkaPublisher(settings)
        self.http = httpx.AsyncClient(
            timeout=httpx.Timeout(settings.http_timeout, connect=settings.http_connect_timeout),
            limits=httpx.Limits(
                max_connections=settings.http_max_connections, max_keepalive_connections=10
            ),
        )
        self.tasks = []
        self.outbox_failures = 0
        self.consumer_delay = 0.0
        self.http_delay = 0.0

    async def read(self, operation):
        """Only opt-in, side-effect-free reads may retry on the primary.

        A missing row is a valid stale replica result, not a connection failure.
        Neither the result nor a stale miss is inserted into the primary cache.
        """
        async def execute(sessions):
            async with asyncio.timeout(self.settings.db_read_timeout):
                async with sessions.begin() as session:
                    await session.execute(text("SET TRANSACTION READ ONLY"))
                    return await operation(session)

        try:
            return await execute(self.read_sessions), "replica"
        except (DBAPIError, PoolTimeout, OSError, TimeoutError):
            log.warning("replica_unavailable_read_primary_fallback")
            return await execute(self.sessions), "primary-fallback"

    async def start(self, handlers=None, extra_workers=()):
        if self.settings.background_workers:
            self.tasks.append(asyncio.create_task(outbox_loop(self), name="outbox"))
            if handlers:
                self.tasks.append(
                    asyncio.create_task(consumer_loop(self, handlers), name="consumer")
                )
            for worker in extra_workers:
                self.tasks.append(asyncio.create_task(worker(self), name=worker.__name__))

    async def close(self):
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        await self.publisher.close()
        await self.http.aclose()
        await self.redis.aclose()
        await self.engine.dispose()
        await self.read_engine.dispose()
