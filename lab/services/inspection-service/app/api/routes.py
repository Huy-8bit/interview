from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query

from app.schemas.inspection import (
    InspectionComplete,
    InspectionCreate,
    InspectionRead,
    InspectionUpdate,
)
from app.services.inspections import InspectionService
from platform_common.api import get_runtime

router = APIRouter(prefix="/inspections", tags=["inspections"])
Key = Annotated[str, Header(alias="Idempotency-Key", min_length=1, max_length=128)]


def service(runtime=Depends(get_runtime)):
    return InspectionService(runtime)


@router.post("", status_code=201, response_model=InspectionRead)
async def create(body: InspectionCreate, idempotency_key: Key, svc=Depends(service)):
    return await svc.create(body, idempotency_key)


@router.get("", response_model=list[InspectionRead])
async def list_inspections(
    vehicle_id: UUID | None = None,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    svc=Depends(service),
):
    return await svc.list(vehicle_id, limit, offset)


@router.get("/{inspection_id}", response_model=InspectionRead)
async def get(inspection_id: UUID, svc=Depends(service)):
    return await svc.get(inspection_id)


@router.patch("/{inspection_id}", response_model=InspectionRead)
async def update(inspection_id: UUID, body: InspectionUpdate, svc=Depends(service)):
    return await svc.update(inspection_id, body)


@router.post("/{inspection_id}/complete", response_model=InspectionRead)
async def complete(inspection_id: UUID, body: InspectionComplete, svc=Depends(service)):
    return await svc.complete(inspection_id, body)
