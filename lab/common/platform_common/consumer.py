import asyncio
import base64
import json
import logging
import os
import time
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


async def deliver(runtime, message, handlers, decoder=None):
    started = time.perf_counter()
    labels = (runtime.settings.service_name, "invalid", message.topic)
    original = None
    error = None
    ct = et = rt = None
    try:
        try:
            original = json.loads(message.value) if message.value else None
            event = decoder(message) if decoder else Event.model_validate(original)
            if event is None:  # A valid Debezium tombstone.
                runtime.metrics.cdc_events.labels(runtime.settings.service_name, "tombstone").inc()
                return
            labels = (runtime.settings.service_name, event.event_type if event.event_type in handlers else "unhandled", message.topic)
            runtime.metrics.events["consumed"].labels(*labels).inc()
            ct = context.correlation_id.set(event.correlation_id)
            et = context.event_id.set(str(event.event_id))
            rt = context.request_id.set(event.request_id or str(event.event_id))
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
                    runtime.metrics.events["processed" if applied else "duplicate"].labels(*labels).inc()
                    if applied and runtime.settings.lab_mode and CRASH_MARKER.exists():
                        CRASH_MARKER.unlink()
                        log.critical("lab_crash_after_db_commit_before_offset_commit")
                        os._exit(70)
                    return
                except Exception as exc:
                    error = exc
                    runtime.metrics.events["failed"].labels(*labels).inc()
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
                        runtime.metrics.events["retried"].labels(*labels).inc()
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
        runtime.metrics.events["dlq"].labels(*labels).inc()
        log.error(
            "consumer_sent_to_dlq", extra={"fields": {"topic": message.topic, "error": str(error)}}
        )
    finally:
        runtime.metrics.event_duration.labels(*labels).observe(time.perf_counter() - started)
        if rt is not None:
            context.request_id.reset(rt)
        if ct is not None:
            context.correlation_id.reset(ct)
        if et is not None:
            context.event_id.reset(et)


async def ensure_fetch_progress(consumer):
    """An idle topic is healthy; backlog with repeated empty polls needs recovery."""
    partitions = consumer.assignment()
    if not partitions:
        return
    ends = await consumer.end_offsets(partitions)
    for partition in partitions:
        if await consumer.position(partition) < ends[partition]:
            raise TimeoutError(f"Consumer fetch stalled with backlog on {partition}")


async def consumer_loop(runtime, handlers: dict, topics=None, decoder=None):
    topics = topics or sorted({name.split(".")[0] + "-events" for name in handlers})
    while True:
        consumer = AIOKafkaConsumer(
            *topics,
            bootstrap_servers=runtime.settings.kafka_bootstrap_servers,
            group_id=runtime.settings.kafka_consumer_group,
            client_id=f"{runtime.settings.service_name}-{runtime.instance_id[:8]}",
            enable_auto_commit=False,
            auto_offset_reset="earliest",
            max_poll_records=1,
            max_poll_interval_ms=runtime.settings.consumer_max_poll_interval_ms,
            request_timeout_ms=runtime.settings.kafka_request_timeout_ms,
            retry_backoff_ms=runtime.settings.kafka_retry_backoff_ms,
        )
        try:
            async with asyncio.timeout(runtime.settings.consumer_fetch_timeout):
                await consumer.start()
            idle_since = time.monotonic()
            while True:
                # Bounded polling revisits coordinator errors instead of waiting forever
                # inside a single getone(), including a stalled assignment after outages.
                async with asyncio.timeout(runtime.settings.consumer_fetch_timeout):
                    batches = await consumer.getmany(timeout_ms=1000, max_records=1)
                if not batches:
                    if time.monotonic() - idle_since >= runtime.settings.consumer_stall_timeout:
                        async with asyncio.timeout(runtime.settings.consumer_fetch_timeout):
                            await ensure_fetch_progress(consumer)
                        idle_since = time.monotonic()
                    continue
                for messages in batches.values():
                    for message in messages:
                        await deliver(runtime, message, handlers, decoder)
                        async with asyncio.timeout(runtime.settings.consumer_fetch_timeout):
                            await consumer.commit(
                                {TopicPartition(message.topic, message.partition): message.offset + 1}
                            )
                idle_since = time.monotonic()
        except Exception:
            log.exception("consumer_restart_from_committed_offset")
        finally:
            await consumer.stop()
        await asyncio.sleep(runtime.settings.retry_base_seconds)
