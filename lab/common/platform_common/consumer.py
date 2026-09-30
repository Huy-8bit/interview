import asyncio
import base64
import json
import logging
import os
from pathlib import Path

from aiokafka import AIOKafkaConsumer, TopicPartition
from sqlalchemy.dialects.postgresql import insert

from platform_common import context
from platform_common.db import utcnow
from platform_common.events import Event
from platform_common.models import ProcessedEvent
from platform_common.outbox import backoff

log = logging.getLogger(__name__)
CRASH_MARKER = Path("/tmp/crash-after-db-commit")


async def process_event(runtime, event: Event, handler) -> bool:
    """INSERT first serializes concurrent deliveries; rollback also rolls back the marker."""
    async with runtime.sessions.begin() as session:
        claimed = await session.scalar(
            insert(ProcessedEvent)
            .values(
                event_id=event.event_id,
                consumer_name=runtime.settings.kafka_consumer_group,
            )
            .on_conflict_do_nothing()
            .returning(ProcessedEvent.event_id)
        )
        if claimed is None:
            log.info("duplicate_event_skipped")
            return False
        await handler(session, event, runtime)
    log.info("event_db_committed", extra={"fields": {"event_type": event.event_type}})
    return True


async def deliver(runtime, message, handlers):
    original = None
    error = None
    ct = et = None
    try:
        try:
            original = json.loads(message.value)
            event = Event.model_validate(original)
            ct = context.correlation_id.set(event.correlation_id)
            et = context.event_id.set(str(event.event_id))
        except Exception as exc:
            error = exc
        else:
            handler = handlers.get(event.event_type)
            if handler is None:
                return  # Other event types on a subscribed domain topic.
            for attempt in range(runtime.settings.consumer_max_retries + 1):
                try:
                    if runtime.consumer_delay:
                        await asyncio.sleep(runtime.consumer_delay)
                    applied = await process_event(runtime, event, handler)
                    if applied and runtime.settings.lab_mode and CRASH_MARKER.exists():
                        CRASH_MARKER.unlink()
                        log.critical("lab_crash_after_db_commit_before_offset_commit")
                        os._exit(70)
                    return
                except Exception as exc:
                    error = exc
                    log.warning(
                        "consumer_retry",
                        extra={
                            "fields": {
                                "attempt": attempt + 1,
                                "error": str(exc),
                                "topic": message.topic,
                            }
                        },
                    )
                    if attempt < runtime.settings.consumer_max_retries:
                        await asyncio.sleep(backoff(attempt, runtime.settings.retry_base_seconds))
        # DLQ ACK is required before committing the source offset. If this fails,
        # the consumer is recreated from its last committed offset.
        retry_count = runtime.settings.consumer_max_retries if ct is not None else 0
        await runtime.publisher.publish(
            message.topic + "-dlq",
            str(message.partition),
            {
                "original_event": original,
                "original_bytes_base64": base64.b64encode(message.value or b"").decode(),
                "failure_reason": f"{type(error).__name__}: {error}"[:4000],
                "failed_at": utcnow().isoformat(),
                "retry_count": retry_count,
                "consumer": runtime.settings.kafka_consumer_group,
                "source": {
                    "topic": message.topic,
                    "partition": message.partition,
                    "offset": message.offset,
                },
            },
        )
        log.error(
            "consumer_sent_to_dlq", extra={"fields": {"topic": message.topic, "error": str(error)}}
        )
    finally:
        if ct is not None:
            context.correlation_id.reset(ct)
        if et is not None:
            context.event_id.reset(et)


async def consumer_loop(runtime, handlers: dict):
    topics = sorted({name.split(".")[0] + "-events" for name in handlers})
    while True:
        consumer = AIOKafkaConsumer(
            *topics,
            bootstrap_servers=runtime.settings.kafka_bootstrap_servers,
            group_id=runtime.settings.kafka_consumer_group,
            client_id=runtime.settings.service_name,
            enable_auto_commit=False,
            auto_offset_reset="earliest",
            max_poll_records=1,
            max_poll_interval_ms=runtime.settings.consumer_max_poll_interval_ms,
        )
        try:
            await consumer.start()
            async for message in consumer:
                await deliver(runtime, message, handlers)
                await consumer.commit(
                    {TopicPartition(message.topic, message.partition): message.offset + 1}
                )
        except Exception:
            log.exception("consumer_restart_from_committed_offset")
        finally:
            await consumer.stop()
        await asyncio.sleep(runtime.settings.retry_base_seconds)
