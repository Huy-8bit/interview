from datetime import datetime
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field

from platform_common.context import correlation_id
from platform_common.db import utcnow
from platform_common.models import OutboxEvent


class Event(BaseModel):
    model_config = ConfigDict(extra="forbid")
    event_id: UUID
    event_type: str = Field(min_length=1, max_length=100)
    event_version: Literal["1.0"] = "1.0"
    occurred_at: datetime
    producer: str
    correlation_id: str
    data: dict


def enqueue(session, settings, event_type: str, aggregate_id, data: dict):
    event = Event(
        event_id=uuid4(),
        event_type=event_type,
        occurred_at=utcnow(),
        producer=settings.service_name,
        correlation_id=correlation_id.get() or str(uuid4()),
        data=data,
    )
    session.add(
        OutboxEvent(
            aggregate_id=str(aggregate_id),
            event_id=event.event_id,
            event_type=event_type,
            topic=event_type.split(".")[0] + "-events",
            payload=event.model_dump(mode="json"),
        )
    )
    return event
