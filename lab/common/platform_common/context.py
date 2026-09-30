from contextvars import ContextVar

request_id: ContextVar[str | None] = ContextVar("request_id", default=None)
correlation_id: ContextVar[str | None] = ContextVar("correlation_id", default=None)
event_id: ContextVar[str | None] = ContextVar("event_id", default=None)
