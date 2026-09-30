from uuid import UUID

from fastapi import APIRouter, Depends

from app.schemas.warranty import Coverage, WarrantyCreate, WarrantyRead
from app.services.warranties import WarrantyService
from platform_common.api import get_runtime

router = APIRouter(prefix="/warranties", tags=["warranties"])


def service(runtime=Depends(get_runtime)):
    return WarrantyService(runtime)


@router.post("", status_code=201, response_model=WarrantyRead)
async def create(body: WarrantyCreate, svc=Depends(service)):
    return await svc.create(body)


@router.get("/vehicle/{vehicle_id}/active", response_model=Coverage)
async def active(vehicle_id: UUID, svc=Depends(service)):
    return await svc.coverage(vehicle_id)


@router.get("/vehicle/{vehicle_id}", response_model=list[WarrantyRead])
async def list_for_vehicle(vehicle_id: UUID, svc=Depends(service)):
    return await svc.list(vehicle_id)


@router.post("/{warranty_id}/activate", response_model=WarrantyRead)
async def activate(warranty_id: UUID, svc=Depends(service)):
    return await svc.transition(warranty_id, "ACTIVE")


@router.post("/{warranty_id}/expire", response_model=WarrantyRead)
async def expire(warranty_id: UUID, svc=Depends(service)):
    return await svc.transition(warranty_id, "EXPIRED")
