from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from platform_common.db import Base, Timestamps


class VehicleReference(Timestamps, Base):
    """Local projection; no cross-service database foreign keys."""

    __tablename__ = "vehicle_references"
    vehicle_id: Mapped[UUID] = mapped_column(primary_key=True)
    vehicle_seen: Mapped[bool] = mapped_column(default=False)
    warranty_seen: Mapped[bool] = mapped_column(default=False)


class Inspection(Timestamps, Base):
    __tablename__ = "inspections"
    __table_args__ = (
        CheckConstraint(
            "status IN ('PENDING','IN_PROGRESS','COMPLETED')", name="inspection_status"
        ),
        CheckConstraint(
            "(status = 'COMPLETED' AND result IN ('PASS','FAIL') AND result IS NOT NULL AND completed_at IS NOT NULL) OR (status != 'COMPLETED' AND result IS NULL AND completed_at IS NULL)",
            name="inspection_completion",
        ),
        CheckConstraint(
            "(result = 'FAIL' AND failure_reason IS NOT NULL AND length(trim(failure_reason)) > 0) OR ((result IS NULL OR result = 'PASS') AND failure_reason IS NULL)",
            name="inspection_failure_reason",
        ),
        Index("ix_inspections_vehicle_created", "vehicle_id", "created_at"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    vehicle_id: Mapped[UUID]
    inspection_type: Mapped[str] = mapped_column(String(50))
    status: Mapped[str] = mapped_column(String(20), default="PENDING")
    result: Mapped[str | None] = mapped_column(String(10))
    failure_reason: Mapped[str | None] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
