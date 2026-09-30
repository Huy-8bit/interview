from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query

from app.schemas.repair import NotificationRead, RepairCreate, RepairRead, RepairUpdate
from app.services.repairs import RepairService
from platform_common.api import get_runtime

router = APIRouter(prefix="/repairs", tags=["repairs"])
Key = Annotated[str, Header(alias="Idempotency-Key", min_length=1, max_length=128)]


def service(runtime=Depends(get_runtime)):
    return RepairService(runtime)


@router.post("", status_code=201, response_model=RepairRead)
async def create(body: RepairCreate, idempotency_key: Key, svc=Depends(service)):
    return await svc.create(body, idempotency_key)


@router.get("", response_model=list[RepairRead])
async def list_repairs(
    vehicle_id: UUID | None = None,
    inspection_id: UUID | None = None,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    svc=Depends(service),
):
    return await svc.list(vehicle_id, inspection_id, limit, offset)


@router.get("/{repair_id}", response_model=RepairRead)
async def get(repair_id: UUID, svc=Depends(service)):
    return await svc.get(repair_id)


@router.patch("/{repair_id}", response_model=RepairRead)
async def update(repair_id: UUID, body: RepairUpdate, svc=Depends(service)):
    return await svc.update(repair_id, body.status)


@router.get("/{repair_id}/notifications", response_model=list[NotificationRead])
async def notifications(repair_id: UUID, svc=Depends(service)):
    return await svc.notifications(repair_id)
