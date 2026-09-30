import asyncio
import json
import os
from uuid import uuid4

import pytest
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer, TopicPartition
from aiokafka.admin import AIOKafkaAdminClient

from platform_common.db import utcnow
from platform_common.events import Event
from scripts.lab_client import poll

pytestmark = pytest.mark.integration


async def wait_committed(group, metadata):
    admin = AIOKafkaAdminClient(bootstrap_servers=os.environ["KAFKA_BOOTSTRAP_SERVERS"])
    try:
        await admin.start()
        partition = TopicPartition(metadata.topic, metadata.partition)

        async def done():
            offsets = await admin.list_consumer_group_offsets(group)
            return partition in offsets and offsets[partition].offset > metadata.offset

        await poll(done)
    finally:
        await admin.close()


async def publish(topic, key, payload):
    producer = AIOKafkaProducer(
        bootstrap_servers=os.environ["KAFKA_BOOTSTRAP_SERVERS"], enable_idempotence=True
    )
    try:
        await producer.start()
        return await producer.send_and_wait(
            topic, key=key.encode(), value=json.dumps(payload).encode()
        )
    finally:
        await producer.stop()


async def test_real_kafka_duplicate_events_do_not_duplicate_resources(client, db):
    vehicle = await client.vehicle()
    await client.warranty(vehicle["id"])
    created = (
        await db(
            "vehicle",
            "SELECT payload FROM outbox_events WHERE aggregate_id = :id AND event_type = 'vehicle.created'",
            id=vehicle["id"],
        )
    )[0]["payload"]
    for _ in range(2):
        ack = await publish("vehicle-events", vehicle["id"], created)
    await wait_committed("warranty-service-v1", ack)
    warranties = await client.json("warranty", "GET", f"/warranties/vehicle/{vehicle['id']}")
    assert len(warranties) == 1
    inspection = await client.inspection(vehicle["id"])
    await client.complete(inspection["id"], "FAIL")
    repair = await client.repair(inspection["id"])
    event = (
        await db(
            "inspection",
            "SELECT payload FROM outbox_events WHERE payload->'data'->>'inspection_id' = :id",
            id=inspection["id"],
        )
    )[0]["payload"]
    for _ in range(2):
        ack = await publish("inspection-events", vehicle["id"], event)
    await wait_committed("repair-service-v1", ack)
    assert len(await client.repairs(inspection["id"])) == 1
    assert len(await client.json("repair", "GET", f"/repairs/{repair['id']}/notifications")) == 1


async def test_consumer_retries_poison_event_then_acknowledges_dlq(db):
    event = Event(
        event_id=uuid4(),
        event_type="inspection.failed",
        occurred_at=utcnow(),
        producer="integration-test",
        correlation_id=str(uuid4()),
        data={"missing": "required failure fields"},
    ).model_dump(mode="json")
    consumer = AIOKafkaConsumer(
        bootstrap_servers=os.environ["KAFKA_BOOTSTRAP_SERVERS"], enable_auto_commit=False
    )
    try:
        await consumer.start()
        await consumer.topics()
        partitions = consumer.partitions_for_topic("inspection-events-dlq")
        tps = [TopicPartition("inspection-events-dlq", p) for p in partitions]
        consumer.assign(tps)
        await consumer.seek_to_end(*tps)
        ack = await publish("inspection-events", event["event_id"], event)
        async with asyncio.timeout(60):
            while True:
                message = await consumer.getone()
                dead = json.loads(message.value)
                if (dead.get("original_event") or {}).get("event_id") == event["event_id"]:
                    break
        assert dead["retry_count"] == 4
        assert dead["consumer"] == "repair-service-v1"
        assert dead["failure_reason"] and dead["failed_at"] and dead["original_bytes_base64"]
        await wait_committed("repair-service-v1", ack)
        rows = await db(
            "repair",
            "SELECT event_id FROM processed_events WHERE event_id = CAST(:id AS uuid)",
            id=event["event_id"],
        )
        assert rows == []
    finally:
        await consumer.stop()
