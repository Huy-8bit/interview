import asyncio
from unittest.mock import Mock

import pytest

from platform_common.runtime import Runtime


@pytest.mark.parametrize("outcome", ["error", "cancelled", "returned"])
async def test_unexpected_worker_exit_restarts_process(monkeypatch, outcome):
    process_exit = Mock()
    monkeypatch.setattr("platform_common.runtime.os._exit", process_exit)
    runtime = Runtime.__new__(Runtime)
    runtime.closing = False

    async def worker():
        if outcome == "error":
            raise RuntimeError("consumer cleanup failed after broker outage")
        if outcome == "cancelled":
            raise asyncio.CancelledError

    task = asyncio.create_task(worker(), name="consumer")
    await asyncio.gather(task, return_exceptions=True)
    runtime.worker_finished(task)
    process_exit.assert_called_once_with(70)


async def test_normal_shutdown_does_not_force_exit(monkeypatch):
    process_exit = Mock()
    monkeypatch.setattr("platform_common.runtime.os._exit", process_exit)
    runtime = Runtime.__new__(Runtime)
    runtime.closing = True
    task = asyncio.create_task(asyncio.sleep(60), name="consumer")
    task.cancel()
    await asyncio.gather(task, return_exceptions=True)
    runtime.worker_finished(task)
    process_exit.assert_not_called()
