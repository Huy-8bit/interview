from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response

from app.schemas.vehicle import VehicleCreate, VehicleRead, VehicleUpdate
from app.services.vehicles import VehicleService
from platform_common.api import get_runtime

router = APIRouter(prefix="/vehicles", tags=["vehicles"])


def service(runtime=Depends(get_runtime)):
    return VehicleService(runtime)


@router.post("", response_model=VehicleRead, status_code=201)
async def create(body: VehicleCreate, svc=Depends(service)):
    return await svc.create(body)


@router.get("", response_model=list[VehicleRead])
async def list_vehicles(
    limit: int = Query(20, ge=1, le=100), offset: int = Query(0, ge=0), svc=Depends(service)
):
    return await svc.list(limit, offset)


@router.get("/{vehicle_id}", response_model=VehicleRead)
async def get(vehicle_id: UUID, response: Response, svc=Depends(service)):
    value, cache = await svc.get(vehicle_id)
    response.headers["X-Cache"] = cache
    return value


@router.patch("/{vehicle_id}", response_model=VehicleRead)
async def update(vehicle_id: UUID, body: VehicleUpdate, svc=Depends(service)):
    return await svc.update(vehicle_id, body)
