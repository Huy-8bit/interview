import asyncio

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import text

from platform_common.api import get_runtime
from platform_common.consumer import CRASH_MARKER

router = APIRouter(prefix="/lab", tags=["lab-only fault injection"])


class Fault(BaseModel):
    seconds: float = Field(default=0, ge=0, le=30)
    count: int = Field(default=1, ge=0, le=100)


@router.post("/crash-next-consumer")
async def crash(runtime=Depends(get_runtime)):
    CRASH_MARKER.touch()
    return {"armed": True, "crash_point": "after DB commit, before offset commit"}


@router.post("/outbox-failures")
async def outbox_fault(body: Fault, runtime=Depends(get_runtime)):
    runtime.outbox_failures = body.count
    return {"failures_remaining": body.count}


@router.post("/consumer-delay")
async def consumer_delay(body: Fault, runtime=Depends(get_runtime)):
    runtime.consumer_delay = body.seconds
    return {"seconds": body.seconds}


@router.post("/http-delay")
async def http_delay(body: Fault, runtime=Depends(get_runtime)):
    runtime.http_delay = body.seconds
    return {"seconds": body.seconds}


@router.post("/hold-db-connections")
async def exhaust_pool(body: Fault, runtime=Depends(get_runtime)):
    async def hold():
        async with runtime.sessions.begin() as session:
            await session.execute(text("SELECT 1"))
            await asyncio.sleep(body.seconds)

    await asyncio.gather(*(hold() for _ in range(body.count)))
    return {"held": body.count, "seconds": body.seconds}
