import asyncio
import json
import logging

from aiokafka import AIOKafkaProducer

log = logging.getLogger(__name__)


class KafkaPublisher:
    def __init__(self, settings):
        self.settings = settings
        self.producer = None
        self._lock = asyncio.Lock()

    async def start(self):
        async with self._lock:
            if self.producer is not None:
                return
            producer = AIOKafkaProducer(
                bootstrap_servers=self.settings.kafka_bootstrap_servers,
                client_id=self.settings.service_name + "-publisher",
                enable_idempotence=True,
                acks="all",
                request_timeout_ms=int(self.settings.kafka_send_timeout * 1000),
            )
            try:
                async with asyncio.timeout(self.settings.kafka_send_timeout):
                    await producer.start()
            except BaseException:
                await producer.stop()
                raise
            self.producer = producer

    async def publish(self, topic: str, key: str, payload: dict):
        await self.start()
        async with asyncio.timeout(self.settings.kafka_send_timeout):
            return await self.producer.send_and_wait(
                topic,
                key=key.encode(),
                value=json.dumps(payload, default=str).encode(),
            )

    async def close(self):
        if self.producer:
            try:
                async with asyncio.timeout(self.settings.kafka_send_timeout):
                    await self.producer.stop()
            except TimeoutError:
                log.warning("kafka_shutdown_timeout")
