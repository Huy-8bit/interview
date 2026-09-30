from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, model_validator


class WarrantyCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    vehicle_id: UUID
    warranty_type: Literal["EXTENDED", "POWERTRAIN"] = "EXTENDED"
    start_date: date
    end_date: date

    @model_validator(mode="after")
    def valid_dates(self):
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        return self


class WarrantyRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    vehicle_id: UUID
    warranty_type: str
    start_date: date
    end_date: date
    status: str
    created_at: datetime
    updated_at: datetime


class Coverage(BaseModel):
    vehicle_id: UUID
    covered: bool
    warranty_id: UUID | None
    checked_at: datetime
