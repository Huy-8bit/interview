from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from platform_common.db import Base, Timestamps, utcnow


class Vehicle(Timestamps, Base):
    __tablename__ = "vehicles"
    __table_args__ = (
        UniqueConstraint("vin", name="vehicles_vin_key"),
        CheckConstraint("status IN ('ACTIVE','INACTIVE')", name="vehicle_status"),
        CheckConstraint("production_year BETWEEN 1886 AND 2100", name="production_year"),
        Index("ix_vehicles_created", "created_at", "id"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    vin: Mapped[str] = mapped_column(String(17))
    model: Mapped[str] = mapped_column(String(100))
    manufacturer: Mapped[str] = mapped_column(String(100))
    production_year: Mapped[int]
    owner_name: Mapped[str] = mapped_column(String(200))
    simulation_run_id: Mapped[UUID | None] = mapped_column(nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="ACTIVE")


class WarrantyProvisionRequest(Timestamps, Base):
    __tablename__ = "warranty_provision_requests"
    vehicle_id: Mapped[UUID] = mapped_column(primary_key=True)
    correlation_id: Mapped[str] = mapped_column(String(128))
    status: Mapped[str] = mapped_column(String(20), default="PENDING", index=True)
    attempts: Mapped[int] = mapped_column(default=0)
    warranty_id: Mapped[UUID | None] = mapped_column(nullable=True)
    last_error: Mapped[str | None] = mapped_column(String(100), nullable=True)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
