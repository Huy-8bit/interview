from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Response

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
    limit: int = Query(20, ge=1, le=100), offset: int = Query(0, ge=0),
    vin: str | None = Query(None, pattern=r"^[A-HJ-NPR-Z0-9]{17}$"), svc=Depends(service),
):
    return await svc.list(limit, offset, vin)


@router.get("/{vehicle_id}", response_model=VehicleRead)
async def get(
    vehicle_id: UUID, response: Response,
    consistency: Literal["primary", "eventual"] = "primary", svc=Depends(service),
):
    if consistency == "eventual":
        value, source = await svc.get_eventual(vehicle_id)
        response.headers["X-Cache"] = "BYPASS"
        response.headers["X-Read-Source"] = source
        return value
    value, cache = await svc.get(vehicle_id)
    response.headers["X-Cache"] = cache
    response.headers["X-Read-Source"] = "cache" if cache == "HIT" else "primary"
    return value


@router.patch("/{vehicle_id}", response_model=VehicleRead)
async def update(vehicle_id: UUID, body: VehicleUpdate, svc=Depends(service)):
    return await svc.update(vehicle_id, body)


@router.delete("/{vehicle_id}", status_code=204)
async def delete_simulation(
    vehicle_id: UUID,
    simulation_run_id: UUID = Header(alias="X-Simulation-Run-ID"),
    svc=Depends(service),
):
    await svc.delete_simulation(vehicle_id, simulation_run_id)
    return Response(status_code=204)
