from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class RepairCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    vehicle_id: UUID
    inspection_id: UUID
    description: str = Field(min_length=1, max_length=4000)


class RepairUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["IN_PROGRESS", "COMPLETED", "CANCELLED"]


class RepairRead(RepairCreate):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    warranty_id: UUID | None = None
    warranty_covered: bool
    status: str
    defect_report_number: str | None = None
    defect_report_sha256: str | None = None
    defect_report_generated_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class NotificationRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    vehicle_id: UUID
    repair_id: UUID
    channel: str
    message: str
    status: str
    created_at: datetime
    updated_at: datetime


class FailedInspection(BaseModel):
    inspection_id: UUID
    vehicle_id: UUID
    failure_reason: str = Field(min_length=1, max_length=4000)
    occurred_at: datetime


class ReportGenerated(BaseModel):
    inspection_id: UUID
    result: Literal["PASS", "FAIL"]
    report_number: str = Field(min_length=1, max_length=40)
    sha256: str = Field(min_length=64, max_length=64)
    generated_at: datetime
