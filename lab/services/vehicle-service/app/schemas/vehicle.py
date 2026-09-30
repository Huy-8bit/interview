from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class VehicleCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    vin: str = Field(pattern=r"^[A-HJ-NPR-Z0-9]{17}$")
    model: str = Field(min_length=1, max_length=100)
    manufacturer: str = Field(min_length=1, max_length=100)
    production_year: int = Field(ge=1886, le=2100)
    owner_name: str = Field(min_length=1, max_length=200)
    simulation_run_id: UUID | None = None

    @model_validator(mode="after")
    def simulation_marker(self):
        if self.simulation_run_id is not None and not self.vin.startswith("TRF"):
            raise ValueError("Simulation vehicles must use a TRF-prefixed VIN")
        return self


class VehicleUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    model: str | None = Field(default=None, min_length=1, max_length=100)
    manufacturer: str | None = Field(default=None, min_length=1, max_length=100)
    production_year: int | None = Field(default=None, ge=1886, le=2100)
    owner_name: str | None = Field(default=None, min_length=1, max_length=200)
    status: Literal["ACTIVE", "INACTIVE"] | None = None

    @model_validator(mode="after")
    def non_null_patch(self):
        if not self.model_fields_set or any(
            getattr(self, k) is None for k in self.model_fields_set
        ):
            raise ValueError("Provide at least one non-null field")
        return self


class VehicleRead(VehicleCreate):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    status: str
    created_at: datetime
    updated_at: datetime
