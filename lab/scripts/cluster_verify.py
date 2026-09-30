"""Read cluster topology and verify live recovery; run inside toolbox."""

import argparse
import asyncio
import json
import os
import time
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from aiokafka import AIOKafkaConsumer, TopicPartition
from aiokafka.admin import AIOKafkaAdminClient
from aiokafka.coordinator.protocol import ConsumerProtocolMemberAssignment
from redis.cluster import key_slot

from platform_common.db import utcnow
from platform_common.kafka import KafkaPublisher
from platform_common.redis import cluster_client, vehicle_cache_key
from scripts.lab_client import LabClient

TOPICS = [
    f"{domain}-{suffix}"
    for domain in ("vehicle", "warranty", "inspection", "repair")
    for suffix in ("events", "events-dlq")
]
BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka-1:9092,kafka-2:9092,kafka-3:9092")
NODES = os.environ.get("REDIS_CLUSTER_NODES", ",".join(f"redis-{i}:6379" for i in range(1, 7)))


async def retry(operation, timeout=90):
    last = None
    try:
        async with asyncio.timeout(timeout):
            while True:
                try:
                    result = await operation()
                    if result:
                        return result
                except Exception as exc:
                    last = exc
                await asyncio.sleep(0.5)
    except TimeoutError as exc:
        raise RuntimeError(f"Cluster verification timed out; last error: {last!r}") from exc


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2, default=str) + "\n")


async def snapshot():
    admin = AIOKafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=3000)
    redis = cluster_client(NODES)
    try:
        await admin.start()
        group_responses = await admin.describe_consumer_groups(["repair-service-v1"])
        group = group_responses[0].groups[0]
        members = []
        assert group[0] == 0, group
        for member in group[5]:
            assignment = ConsumerProtocolMemberAssignment.decode(member[4])
            members.append(
                {
                    "client_id": member[1],
                    "partitions": [(tp.topic, tp.partition) for tp in assignment.partitions()],
                }
            )
        return {
            "recorded_at": utcnow().isoformat(),
            "kafka": await admin.describe_cluster(),
            "topics": await admin.describe_topics(TOPICS),
            "repair_group": {"state": group[2], "members": members},
            "redis_info": await redis.cluster_info(),
            "redis_nodes": await redis.cluster_nodes(),
        }
    finally:
        await admin.close()
        await redis.aclose()


def assert_topology(state, *, kafka_nodes=3, full_redis=True, members=None):
    brokers = {b["node_id"] for b in state["kafka"]["brokers"]}
    assert len(brokers) == kafka_nodes, state["kafka"]
    assert state["kafka"]["controller_id"] in brokers
    assert len(state["topics"]) == 8
    for topic in state["topics"]:
        assert topic["error_code"] == 0 and len(topic["partitions"]) >= 3, topic
        for part in topic["partitions"]:
            assert part["error_code"] == 0 and part["leader"] in brokers, part
            assert set(part["replicas"]) == {1, 2, 3}, part
            assert len(part["isr"]) == kafka_nodes, part
    info = state["redis_info"]
    assert info["cluster_state"] == "ok" and int(info["cluster_slots_ok"]) == 16384, info
    assert int(info["cluster_known_nodes"]) == 6 and int(info["cluster_size"]) == 3
    nodes = state["redis_nodes"].values()
    active_masters = [n for n in nodes if "master" in n["flags"] and "fail" not in n["flags"]]
    assert len(active_masters) == 3
    if full_redis:
        assert sum("slave" in n["flags"] for n in nodes) == 3
        assert all(n["connected"] and "fail" not in n["flags"] for n in nodes)
    if members is not None:
        group = state["repair_group"]
        assert group["state"] == "Stable" and len(group["members"]) == members, group
        assignments = [tuple(p) for m in group["members"] for p in m["partitions"]]
        topic = next(t for t in state["topics"] if t["topic"] == "inspection-events")
        expected = {("inspection-events", p["partition"]) for p in topic["partitions"]}
        assert len(assignments) == len(set(assignments)) == len(expected), group
        assert set(assignments) == expected, group
        if members == len(expected):
            assert all(len(m["partitions"]) == 1 for m in group["members"]), group


async def workflow():
    client = LabClient()
    try:
        vehicle = await client.vehicle()
        await client.warranty(vehicle["id"])
        key = str(uuid4())
        inspection = await client.inspection(vehicle["id"], key=key)
        duplicate = await client.inspection(vehicle["id"], key=key)
        assert duplicate["id"] == inspection["id"]
        await client.complete(inspection["id"], "FAIL")
        repair = await client.repair(inspection["id"])
        assert repair["warranty_covered"] is True
        assert len(await client.repairs(inspection["id"])) == 1
        notifications = await client.json("repair", "GET", f"/repairs/{repair['id']}/notifications")
        assert len(notifications) == 1
        await client.json("vehicle", "GET", f"/vehicles/{vehicle['id']}")
        hit = await client.request("vehicle", "GET", f"/vehicles/{vehicle['id']}")
        assert hit.headers["X-Cache"] == "HIT", hit.text
        await client.json(
            "vehicle",
            "PATCH",
            f"/vehicles/{vehicle['id']}",
            json={"owner_name": "Cluster verified"},
        )
        fresh = await client.json("vehicle", "GET", f"/vehicles/{vehicle['id']}")
        assert fresh["owner_name"] == "Cluster verified"
        return {
            "vehicle_id": vehicle["id"],
            "inspection_id": inspection["id"],
            "repair_id": repair["id"],
            "cache": "HIT and invalidation verified",
            "idempotency": "same resource",
            "notifications": 1,
        }
    finally:
        await client.close()


async def wait_signal(directory):
    async def exists():
        return (directory / "go").exists()

    await retry(exists, 120)


async def watch_kafka(args):
    directory = Path(args.directory)
    before = await snapshot()
    broker_id = int(args.node.split("-")[-1])
    topic = next(t for t in before["topics"] if t["topic"] == "repair-events")
    # A controller is not guaranteed to lead any repair-events partition after failovers.
    # The separate partition-leader drill explicitly selects that topic's live leader.
    candidates = [p for p in topic["partitions"] if p["leader"] == broker_id]
    selected = min(candidates or topic["partitions"], key=lambda p: p["partition"])
    partition = selected["partition"]
    # Choose a key that aiokafka's default partitioner routes to the selected leader.
    from aiokafka.partitioner import DefaultPartitioner

    partitioner = DefaultPartitioner()
    partitions = sorted(p["partition"] for p in topic["partitions"])
    key = next(
        str(i)
        for i in range(10000)
        if partitioner(str(i).encode(), partitions, partitions) == partition
    )
    settings = SimpleNamespace(
        service_name="cluster-recovery-probe",
        kafka_bootstrap_servers=BOOTSTRAP,
        kafka_send_timeout=5,
        kafka_request_timeout_ms=10000,
        kafka_retry_backoff_ms=200,
    )
    publisher = KafkaPublisher(settings)
    consumer = AIOKafkaConsumer(bootstrap_servers=BOOTSTRAP, enable_auto_commit=False)
    event = {
        "event_id": str(uuid4()),
        "event_type": "repair.cluster_probe",
        "event_version": "1.0",
        "occurred_at": utcnow().isoformat(),
        "producer": "cluster-verifier",
        "correlation_id": str(uuid4()),
        "data": {"purpose": "leader failover verification"},
    }
    try:
        await consumer.start()
        tp = TopicPartition("repair-events", partition)
        consumer.assign([tp])
        await consumer.seek_to_end(tp)
        warm = await publisher.publish("repair-events", key, event)
        assert warm.partition == partition
        await asyncio.wait_for(consumer.getone(tp), 10)
        save(
            directory / "ready.json",
            {
                "node": args.node,
                "topic": "repair-events",
                "partition": partition,
                "leader_before": selected["leader"],
                "metadata_controller_hint": before["kafka"]["controller_id"],
            },
        )
        await wait_signal(directory)
        started = time.monotonic()
        event["event_id"] = str(uuid4())
        errors = []

        async def send():
            try:
                ack = await publisher.publish("repair-events", key, event)
                return {"partition": ack.partition, "offset": ack.offset}
            except Exception as exc:
                errors.append(type(exc).__name__)
                return None

        ack = await retry(send)
        async with asyncio.timeout(30):
            while True:
                record = await consumer.getone(tp)
                if json.loads(record.value)["event_id"] == event["event_id"]:
                    break
        save(
            directory / "result.json",
            {
                "node": args.node,
                "partition": partition,
                "ack": ack,
                "consumer_received_same_event": True,
                "same_producer_and_consumer_instances": True,
                "recovery_seconds": round(time.monotonic() - started, 3),
                "transient_errors": errors,
            },
        )
    finally:
        await publisher.close()
        await consumer.stop()


async def watch_redis(args):
    directory = Path(args.directory)
    redis = cluster_client(NODES)
    client = LabClient()
    try:
        nodes = await redis.cluster_nodes()
        target = next(n for n in nodes.values() if n["hostname"] == args.node)
        master = (
            target
            if "master" in target["flags"]
            else next(n for n in nodes.values() if n["node_id"] == target["master_id"])
        )
        ranges = [(int(a), int(b)) for a, b in master["slots"]]

        def belongs(key):
            return any(a <= key_slot(key.encode()) <= b for a, b in ranges)

        vehicle = None
        for _ in range(50):
            candidate = await client.vehicle()
            if belongs(vehicle_cache_key(candidate["id"])):
                vehicle = candidate
                break
        assert vehicle, "Could not find a vehicle key on target master"
        path = f"/vehicles/{vehicle['id']}"
        await client.json("vehicle", "GET", path)
        assert (await client.request("vehicle", "GET", path)).headers["X-Cache"] == "HIT"
        key = vehicle_cache_key(vehicle["id"]) + ":probe"
        await redis.set(key, "before", ex=300)
        idem_key = str(uuid4())
        inspection = await client.inspection(vehicle["id"], key=idem_key)
        save(
            directory / "ready.json",
            {
                "node": args.node,
                "role_before": target["flags"],
                "master_id_before": master["node_id"],
                "master_before": master["hostname"],
                "key": key,
                "slot": key_slot(key.encode()),
                "vehicle_id": vehicle["id"],
            },
        )
        await wait_signal(directory)
        started = time.monotonic()
        errors, cache_results, http_statuses = [], [], []

        async def recovered():
            response = await client.request("vehicle", "GET", path)
            http_statuses.append(response.status_code)
            assert response.status_code == 200 and response.json()["id"] == vehicle["id"], (
                response.text
            )
            cache_results.append(response.headers.get("X-Cache"))
            try:
                async with asyncio.timeout(3):
                    await redis.set(key, "after", ex=300)
                    assert await redis.get(key) == "after"
                    info = await redis.cluster_info()
                    return info["cluster_state"] == "ok"
            except Exception as exc:
                errors.append(type(exc).__name__)
                return False

        await retry(recovered)
        assert all(status == 200 for status in http_statuses), http_statuses
        duplicate = await client.inspection(vehicle["id"], key=idem_key)
        assert duplicate["id"] == inspection["id"]
        await client.json("vehicle", "PATCH", path, json={"owner_name": "After Redis failover"})
        assert (await client.json("vehicle", "GET", path))["owner_name"] == "After Redis failover"
        assert (await client.request("vehicle", "GET", path)).headers["X-Cache"] == "HIT"
        topology = await redis.cluster_nodes()
        owners = [
            n
            for n in topology.values()
            if "master" in n["flags"]
            and "fail" not in n["flags"]
            and any(int(a) <= key_slot(key.encode()) <= int(b) for a, b in n["slots"])
        ]
        assert len(owners) == 1
        if "master" in target["flags"]:
            assert owners[0]["node_id"] != target["node_id"], topology
            promoted = next(n for n in nodes.values() if n["node_id"] == owners[0]["node_id"])
            assert promoted["master_id"] == master["node_id"], promoted
        save(
            directory / "result.json",
            {
                "node": args.node,
                "slot_owner_after": owners[0]["hostname"],
                "same_redis_client_instance": True,
                "cache_results_during_recovery": cache_results,
                "http_statuses_during_recovery": http_statuses,
                "cache_hit_and_invalidation_after_recovery": True,
                "same_inspection_after_retry": duplicate["id"],
                "recovery_seconds": round(time.monotonic() - started, 3),
                "transient_errors": errors,
            },
        )
    finally:
        await redis.aclose()
        await client.close()


async def main(args):
    if args.command in {"watch-kafka", "watch-redis"}:
        return await (watch_kafka(args) if args.command == "watch-kafka" else watch_redis(args))
    if args.command == "workflow":
        result = await workflow()
    elif args.command == "select":
        state = await snapshot()
        if args.kind == "kafka-leader":
            topic = next(t for t in state["topics"] if t["topic"] == "repair-events")
            partition = next(p for p in topic["partitions"] if p["partition"] == 0)
            print("kafka-" + str(partition["leader"]))
        else:
            role = "master" if args.kind == "redis-master" else "slave"
            print(
                sorted(
                    n["hostname"]
                    for n in state["redis_nodes"].values()
                    if role in n["flags"] and "fail" not in n["flags"]
                )[0]
            )
        return
    else:

        async def checked():
            state = await snapshot()
            if args.command == "verify":
                assert_topology(
                    state,
                    kafka_nodes=args.kafka_nodes,
                    full_redis=not args.redis_degraded,
                    members=args.members,
                )
                if not args.redis_degraded:
                    redis = cluster_client(NODES)
                    try:
                        replicas = await redis.info("replication", target_nodes=redis.ALL_NODES)
                        assert (
                            sum(v.get("master_link_status") == "up" for v in replicas.values()) == 3
                        ), replicas
                    finally:
                        await redis.aclose()
            return state

        result = await retry(checked)
    if args.output:
        save(args.output, result)
    print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=["snapshot", "verify", "workflow", "select", "watch-kafka", "watch-redis"],
    )
    parser.add_argument("--output")
    parser.add_argument(
        "--kind", choices=["kafka-leader", "redis-master", "redis-replica"]
    )
    parser.add_argument("--node")
    parser.add_argument("--directory")
    parser.add_argument("--kafka-nodes", type=int, default=3)
    parser.add_argument("--redis-degraded", action="store_true")
    parser.add_argument("--members", type=int)
    asyncio.run(main(parser.parse_args()))
