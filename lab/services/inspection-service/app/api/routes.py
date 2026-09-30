from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Response

from app.schemas.inspection import (
    InspectionComplete,
    InspectionCreate,
    InspectionRead,
    InspectionUpdate,
    ReportRead,
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


@router.get("/{inspection_id}/report", response_model=ReportRead)
async def report(inspection_id: UUID, svc=Depends(service)):
    return await svc.report(inspection_id)


@router.get("/{inspection_id}/report.pdf", response_class=Response, responses={200: {"content": {"application/pdf": {}}}})
async def report_pdf(inspection_id: UUID, svc=Depends(service)):
    row = await svc.report(inspection_id, document=True)
    return Response(row.document, media_type="application/pdf", headers={
        "Content-Disposition": f'inline; filename="{row.report_number}.pdf"', "ETag": f'"{row.sha256}"'})


@router.get("/workflows/{vehicle_id}")
async def workflow(vehicle_id: UUID, runtime=Depends(get_runtime)):
    from sqlalchemy import select

    from app.models.inspection import VehicleReference, VehicleWarrantyProjection
    from platform_common.errors import DomainError
    async with runtime.sessions() as session:
        row = await session.get(VehicleReference, vehicle_id)
        if row is None:
            raise DomainError(404, "workflow_not_ready", "Neither input has arrived yet")
        warranties = (await session.scalars(select(VehicleWarrantyProjection).where(VehicleWarrantyProjection.vehicle_id == vehicle_id))).all()
        return {"vehicle_id": vehicle_id, "status": row.workflow_status, "vehicle_seen": row.vehicle_seen,
                "warranty_seen": row.warranty_seen, "warranty_id": row.warranty_id, "prepared_at": row.prepared_at,
                "warranties": [{"warranty_id": w.warranty_id, "status": w.warranty_status, "deleted": w.is_deleted,
                               "source_lsn": w.source_lsn, "synced_at": w.synced_at} for w in warranties]}
