import asyncio
import logging
from uuid import uuid4

import httpx
from redis.asyncio import Redis

from platform_common.consumer import consumer_loop
from platform_common.db import database
from platform_common.kafka import KafkaPublisher
from platform_common.outbox import outbox_loop
from platform_common.redis import RedisSupport

log = logging.getLogger(__name__)


class Runtime:
    def __init__(self, settings):
        self.instance_id = str(uuid4())
        self.settings = settings
        self.engine, self.sessions = database(settings)
        self.redis = Redis.from_url(
            settings.redis_url,
            decode_responses=True,
            socket_connect_timeout=settings.redis_timeout,
            socket_timeout=settings.redis_timeout,
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
