from datetime import date
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from platform_common.db import Base, Timestamps


class Warranty(Timestamps, Base):
    __tablename__ = "warranties"
    __table_args__ = (
        UniqueConstraint("vehicle_id", "warranty_type", name="uq_warranty_vehicle_type"),
        CheckConstraint("end_date >= start_date", name="warranty_dates"),
        CheckConstraint("status IN ('PENDING','ACTIVE','EXPIRED')", name="warranty_status"),
        Index("ix_warranties_coverage", "vehicle_id", "status", "start_date", "end_date"),
        Index("ix_warranties_expiry", "status", "end_date"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    vehicle_id: Mapped[UUID]
    warranty_type: Mapped[str] = mapped_column(String(50))
    start_date: Mapped[date]
    end_date: Mapped[date]
    status: Mapped[str] = mapped_column(String(20), default="PENDING")
