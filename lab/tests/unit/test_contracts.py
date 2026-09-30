from uuid import uuid4

import pytest
from pydantic import ValidationError

from platform_common.db import utcnow
from platform_common.events import Event
from platform_common.idempotency import fingerprint
from platform_common.outbox import backoff

pytestmark = pytest.mark.unit


def test_request_fingerprint_is_order_independent_but_payload_sensitive():
    assert fingerprint({"a": 1, "b": 2}) == fingerprint({"b": 2, "a": 1})
    assert fingerprint({"a": 1}) != fingerprint({"a": 2})


def test_retry_is_exponential_and_capped():
    assert [backoff(i) for i in range(4)] == [1, 2, 4, 8]
    assert backoff(100000) == 60


def test_event_version_is_explicitly_validated():
    data = dict(
        event_id=uuid4(),
        event_type="vehicle.created",
        occurred_at=utcnow(),
        producer="test",
        correlation_id=str(uuid4()),
        data={},
    )
    assert Event(**data).event_version == "1.0"
    with pytest.raises(ValidationError):
        Event(**data, event_version="2.0")
