import json
import logging
from datetime import UTC, datetime

from platform_common import context


class JsonFormatter(logging.Formatter):
    def __init__(self, service: str):
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        value = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "service": self.service,
            "request_id": context.request_id.get(),
            "correlation_id": context.correlation_id.get(),
            "trace_id": None,
            "event_id": context.event_id.get(),
            "message": record.getMessage(),
            "logger": record.name,
        }
        value.update(getattr(record, "fields", {}))
        if record.exc_info:
            value["exception"] = self.formatException(record.exc_info)
        return json.dumps(value, default=str, ensure_ascii=False)


def configure_logging(service: str, level: str):
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter(service))
    logging.basicConfig(level=level, handlers=[handler], force=True)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True
    logging.getLogger("aiokafka").setLevel(logging.WARNING)
