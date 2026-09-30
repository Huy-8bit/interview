from unittest.mock import AsyncMock, Mock

import pytest
from aiokafka import TopicPartition

from platform_common.consumer import ensure_fetch_progress

pytestmark = pytest.mark.unit


@pytest.mark.parametrize("position,end", [(5, 5), (5, 6)])
async def test_distinguishes_idle_topic_from_stalled_fetcher(position, end):
    tp = TopicPartition("vehicle-events", 0)
    consumer = Mock()
    consumer.assignment.return_value = {tp}
    consumer.end_offsets = AsyncMock(return_value={tp: end})
    consumer.position = AsyncMock(return_value=position)
    if end > position:
        with pytest.raises(TimeoutError, match="fetch stalled"):
            await ensure_fetch_progress(consumer)
    else:
        await ensure_fetch_progress(consumer)


async def test_unassigned_group_member_is_not_restarted_for_being_idle():
    consumer = Mock()
    consumer.assignment.return_value = set()
    consumer.end_offsets = AsyncMock()
    await ensure_fetch_progress(consumer)
    consumer.end_offsets.assert_not_awaited()
