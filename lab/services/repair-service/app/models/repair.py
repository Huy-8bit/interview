from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from platform_common.db import Base, Timestamps


class RepairRequest(Timestamps, Base):
    __tablename__ = "repair_requests"
    __table_args__ = (
        UniqueConstraint("inspection_id", name="repair_requests_inspection_id_key"),
        CheckConstraint(
            "status IN ('OPEN','IN_PROGRESS','COMPLETED','CANCELLED')", name="repair_status"
        ),
        Index("ix_repairs_vehicle_created", "vehicle_id", "created_at"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    vehicle_id: Mapped[UUID]
    inspection_id: Mapped[UUID]
    warranty_id: Mapped[UUID | None] = mapped_column(nullable=True)
    warranty_covered: Mapped[bool]
    status: Mapped[str] = mapped_column(String(20), default="OPEN")
    description: Mapped[str] = mapped_column(Text)
    # Reference to the exact defect report version from inspection.report.generated.
    defect_report_number: Mapped[str | None] = mapped_column(String(40))
    defect_report_sha256: Mapped[str | None] = mapped_column(String(64))
    defect_report_generated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Notification(Timestamps, Base):
    __tablename__ = "notifications"
    __table_args__ = (
        UniqueConstraint("repair_id", "channel", name="uq_notification_repair_channel"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    vehicle_id: Mapped[UUID]
    repair_id: Mapped[UUID] = mapped_column(ForeignKey("repair_requests.id"))
    channel: Mapped[str] = mapped_column(String(20), default="LOG")
    message: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="SIMULATED")
