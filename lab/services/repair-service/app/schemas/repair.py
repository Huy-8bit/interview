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
    warranty_covered: bool
    status: str
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
