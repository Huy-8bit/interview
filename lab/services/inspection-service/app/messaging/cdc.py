"""Decode Kafka records from Debezium PostgreSQL, including snapshot and tombstone."""
import json
from datetime import UTC, datetime
from uuid import NAMESPACE_URL, UUID, uuid5

from platform_common.events import Event

CDC_TOPIC = "warranty-cdc.public.warranties"
TOPICS = ("vehicle-events", CDC_TOPIC)


def unwrap(value):
    parsed = json.loads(value)
    return parsed.get("payload", parsed) if isinstance(parsed, dict) else parsed


def decode(message):
    if message.topic != CDC_TOPIC:
        return Event.model_validate_json(message.value)
    if message.value is None:
        return None
    payload = unwrap(message.value)
    if payload is None:  # JSON converter may emit a schema-wrapped null.
        return None
    op = payload.get("op")
    if op not in ("c", "u", "d", "r"):
        raise ValueError("Unsupported warranty CDC operation")
    source = payload["source"]
    if (source.get("db"), source.get("schema"), source.get("table")) != ("warranty_db", "public", "warranties"):
        raise ValueError("CDC record has an unexpected source")
    row = payload.get("before") if op == "d" else payload.get("after")
    if not row:
        raise ValueError("CDC row image missing; configure REPLICA IDENTITY FULL")
    key = unwrap(message.key) if message.key else None
    if key and UUID(str(key["id"])) != UUID(str(row["id"])):
        raise ValueError("CDC key differs from row ID")
    if source.get("lsn") is None:
        raise ValueError("CDC source LSN is required for replay ordering")
    identifier = uuid5(NAMESPACE_URL, f"{message.topic}:{message.partition}:{message.offset}")
    timestamp = source.get("ts_ms") or payload.get("ts_ms")
    return Event(event_id=identifier, event_type="warranty.cdc", occurred_at=datetime.fromtimestamp(timestamp / 1000, UTC),
                 producer="debezium-warranty", correlation_id=row.get("correlation_id") or str(identifier),
                 data={"envelope": payload, "partition": message.partition, "offset": message.offset})
