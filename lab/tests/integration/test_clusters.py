"""Assertions against the real three-broker / six-node cluster, no mocks."""

import os
from uuid import uuid4

import pytest
from aiokafka.admin import AIOKafkaAdminClient

from platform_common.redis import UNLOCK
from scripts.cluster_verify import TOPICS

pytestmark = pytest.mark.integration


async def test_kafka_topics_have_three_replicas_and_full_isr():
    admin = AIOKafkaAdminClient(bootstrap_servers=os.environ["KAFKA_BOOTSTRAP_SERVERS"])
    try:
        await admin.start()
        cluster = await admin.describe_cluster()
        assert {node["node_id"] for node in cluster["brokers"]} == {1, 2, 3}
        for topic in await admin.describe_topics(TOPICS):
            assert len(topic["partitions"]) >= 3
            for partition in topic["partitions"]:
                assert set(partition["replicas"]) == set(partition["isr"]) == {1, 2, 3}
                assert partition["leader"] in {1, 2, 3}
    finally:
        await admin.close()


async def test_redis_has_all_slots_and_three_live_replica_links(redis_client):
    info = await redis_client.cluster_info()
    assert info["cluster_state"] == "ok"
    assert int(info["cluster_slots_ok"]) == 16384
    nodes = await redis_client.cluster_nodes()
    assert len(nodes) == 6
    assert sum("master" in node["flags"] for node in nodes.values()) == 3
    assert sum("slave" in node["flags"] for node in nodes.values()) == 3
    replication = await redis_client.info("replication", target_nodes=redis_client.ALL_NODES)
    assert sum(node.get("master_link_status") == "up" for node in replication.values()) == 3


async def test_cluster_lock_cannot_be_released_by_previous_owner(redis_client):
    key = f"lock:test:{uuid4()}"
    await redis_client.set(key, "new-owner", nx=True, ex=10)
    assert await redis_client.eval(UNLOCK, 1, key, "old-owner") == 0
    assert await redis_client.get(key) == "new-owner"
    assert await redis_client.eval(UNLOCK, 1, key, "new-owner") == 1


async def test_unreachable_cluster_seeds_follow_safe_fallback_contract():
    from types import SimpleNamespace

    from platform_common.redis import RedisSupport, cluster_client, vehicle_cache_key

    # Real refused connections: discovery raises RedisClusterException, not RedisError.
    unreachable = cluster_client("redis-1:1,redis-2:1,redis-3:1", timeout=0.1)
    settings = SimpleNamespace(
        service_name="outage-regression", redis_operation_timeout=2, lock_timeout=1, cache_ttl=60
    )
    support = RedisSupport(unreachable, settings)
    try:
        key = vehicle_cache_key(uuid4())
        assert await support.cache_read(key) == (None, None)
        assert await support.get_json("idem:unreachable") is None
        await support.cache_fill(key, {"id": "probe"}, "0")
        await support.invalidate(key)
        await support.set_json("idem:unreachable", {"state": "processing"}, 1)
        async with support.lock("resource") as acquired:
            assert acquired is False  # Caller continues under existing DB constraints/ledger.
    finally:
        await unreachable.aclose()
