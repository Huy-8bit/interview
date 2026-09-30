import asyncio
import json
import logging
from contextlib import asynccontextmanager
from uuid import uuid4

from redis.asyncio.cluster import ClusterNode, RedisCluster
from redis.asyncio.retry import Retry
from redis.backoff import ExponentialBackoff
from redis.exceptions import RedisClusterException, RedisError

from platform_common.errors import TransientError

log = logging.getLogger(__name__)
UNLOCK = "if redis.call('GET',KEYS[1]) == ARGV[1] then return redis.call('DEL',KEYS[1]) else return 0 end"
CACHE_READ = "return {redis.call('GET',KEYS[1]) or '', redis.call('GET',KEYS[2]) or '0'}"
CACHE_SET = "if (redis.call('GET',KEYS[2]) or '0') == ARGV[1] then return redis.call('SET',KEYS[1],ARGV[2],'EX',ARGV[3]) end"
CACHE_INVALIDATE = "redis.call('INCR',KEYS[2]); return redis.call('DEL',KEYS[1])"


def cluster_client(nodes: str, *, timeout=0.5, client_name=None):
    startup_nodes = []
    for endpoint in nodes.split(","):
        host, port = endpoint.strip().rsplit(":", 1)
        startup_nodes.append(ClusterNode(host, int(port)))
    return RedisCluster(
        startup_nodes=startup_nodes,
        decode_responses=True,
        socket_connect_timeout=timeout,
        socket_timeout=timeout,
        require_full_coverage=True,
        dynamic_startup_nodes=False,
        reinitialize_steps=1,
        retry=Retry(ExponentialBackoff(base=0.1, cap=0.2), 1),
        max_connections=20,
        client_name=client_name,
    )


def vehicle_cache_key(vehicle_id):
    # Both this key and its :generation key must use the same Redis Cluster slot.
    return f"vehicle:{{{vehicle_id}}}"


class RedisSupport:
    def __init__(self, client, settings):
        self.client, self.settings = client, settings

    async def execute(self, operation):
        # Cluster discovery/redirections/retries must not consume an unbounded API budget.
        async with asyncio.timeout(self.settings.redis_operation_timeout):
            return await operation

    async def get_json(self, key):
        try:
            value = await self.execute(self.client.get(key))
            return json.loads(value) if value else None
        except (RedisError, RedisClusterException, TimeoutError, ValueError, TypeError):
            log.warning("redis_read_unavailable", extra={"fields": {"key": key}})
            return None

    async def set_json(self, key, value, ttl):
        try:
            await self.execute(self.client.set(key, json.dumps(value), ex=ttl))
        except (RedisError, RedisClusterException, TimeoutError):
            log.warning("redis_write_unavailable")

    async def cache_read(self, key):
        try:
            value, generation = await self.execute(
                self.client.eval(CACHE_READ, 2, key, key + ":generation")
            )
            return (json.loads(value) if value else None), generation
        except (RedisError, RedisClusterException, TimeoutError, ValueError, TypeError):
            log.warning("cache_bypass")
            return None, None

    async def cache_fill(self, key, value, generation):
        if generation is None:
            return
        try:
            await self.execute(
                self.client.eval(
                    CACHE_SET,
                    2,
                    key,
                    key + ":generation",
                    generation,
                    json.dumps(value),
                    self.settings.cache_ttl,
                )
            )
        except (RedisError, RedisClusterException, TimeoutError):
            log.warning("cache_fill_failed")

    async def invalidate(self, key):
        try:
            await self.execute(self.client.eval(CACHE_INVALIDATE, 2, key, key + ":generation"))
        except (RedisError, RedisClusterException, TimeoutError):
            log.warning("cache_invalidation_failed_ttl_will_expire", extra={"fields": {"key": key}})

    @asynccontextmanager
    async def lock(self, name: str, *, contention_is_error=True):
        key, token, acquired = f"lock:{self.settings.service_name}:{name}", str(uuid4()), False
        try:
            acquired = bool(
                await self.execute(
                    self.client.set(key, token, nx=True, ex=self.settings.lock_timeout)
                )
            )
        except (RedisError, RedisClusterException, TimeoutError):
            log.warning("lock_bypass_using_database_constraints")
        else:
            if not acquired and contention_is_error:
                raise TransientError("resource lock busy")
        try:
            yield acquired
        finally:
            if acquired:
                try:
                    await self.execute(self.client.eval(UNLOCK, 1, key, token))
                except (RedisError, RedisClusterException, TimeoutError):
                    log.warning("lock_release_failed_wait_for_expiry")
