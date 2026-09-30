from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class InspectionCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    vehicle_id: UUID
    inspection_type: Literal["DELIVERY", "PERIODIC", "DIAGNOSTIC"] = "PERIODIC"
    notes: str | None = Field(default=None, max_length=4000)


class InspectionUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    notes: str | None = Field(default=None, max_length=4000)
    status: Literal["IN_PROGRESS"] | None = None

    @model_validator(mode="after")
    def valid_patch(self):
        if not self.model_fields_set or ("status" in self.model_fields_set and self.status is None):
            raise ValueError("Provide notes or a non-null IN_PROGRESS status")
        return self


class InspectionComplete(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    result: Literal["PASS", "FAIL"]
    failure_reason: str | None = Field(default=None, min_length=1, max_length=4000)
    notes: str | None = Field(default=None, max_length=4000)

    @model_validator(mode="after")
    def result_reason(self):
        if self.result == "FAIL" and not self.failure_reason:
            raise ValueError("FAIL requires failure_reason")
        if self.result == "PASS" and self.failure_reason is not None:
            raise ValueError("PASS cannot have failure_reason")
        return self


class ReportRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    inspection_id: UUID
    kind: str
    status: str
    priority: Literal["HIGH", "NORMAL"]
    task_id: UUID
    attempts: int
    dispatch_attempts: int
    report_number: str | None
    sha256: str | None
    size_bytes: int | None
    worker: str | None
    last_error: str | None
    created_at: datetime
    queued_at: datetime | None
    started_at: datetime | None
    generated_at: datetime | None
    failed_at: datetime | None

    @field_validator("priority", mode="before")
    @classmethod
    def priority_level(cls, value):
        return value if isinstance(value, str) else "HIGH" if value > 4 else "NORMAL"


class InspectionRead(BaseModel):
    warranty_id: UUID | None = None
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    vehicle_id: UUID
    inspection_type: str
    status: str
    result: str | None
    failure_reason: str | None
    notes: str | None
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None
