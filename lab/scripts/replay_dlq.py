"""Replay one explicit DLQ offset after the underlying error has been fixed."""

import argparse
import asyncio
import json
import os

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer, TopicPartition


async def main(args):
    bootstrap = os.environ["KAFKA_BOOTSTRAP_SERVERS"]
    consumer = AIOKafkaConsumer(bootstrap_servers=bootstrap, enable_auto_commit=False)
    producer = AIOKafkaProducer(bootstrap_servers=bootstrap, enable_idempotence=True)
    try:
        await consumer.start()
        await producer.start()
        partition = TopicPartition(args.topic, args.partition)
        consumer.assign([partition])
        consumer.seek(partition, args.offset)
        record = await asyncio.wait_for(consumer.getone(), 10)
        if record.offset != args.offset:
            raise SystemExit("Requested offset not available")
        dlq = json.loads(record.value)
        event = dlq.get("original_event")
        if not isinstance(event, dict) or "event_id" not in event:
            raise SystemExit("Malformed input needs manual correction, not automatic replay")
        topic = dlq["source"]["topic"]
        if args.topic != topic + "-dlq":
            raise SystemExit("Source topic mismatch")
        data = event["data"]
        key = str(data.get("vehicle_id") or data.get("id") or event["event_id"])
        await producer.send_and_wait(topic, key=key.encode(), value=json.dumps(event).encode())
        print(f"Replayed {event['event_id']} to {topic}; original DLQ record retained")
    finally:
        await producer.stop()
        await consumer.stop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "topic",
        choices=[f"{d}-events-dlq" for d in ["vehicle", "warranty", "inspection", "repair"]],
    )
    parser.add_argument("partition", type=int)
    parser.add_argument("offset", type=int)
    asyncio.run(main(parser.parse_args()))
