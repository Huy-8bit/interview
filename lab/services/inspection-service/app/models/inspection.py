from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from platform_common.db import Base, Timestamps, utcnow


class VehicleReference(Timestamps, Base):
    """Local projection; no cross-service database foreign keys."""

    __tablename__ = "vehicle_references"
    vehicle_id: Mapped[UUID] = mapped_column(primary_key=True)
    vehicle_seen: Mapped[bool] = mapped_column(default=False)
    warranty_seen: Mapped[bool] = mapped_column(default=False)
    vehicle_payload: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    source_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    warranty_id: Mapped[UUID | None] = mapped_column(nullable=True)
    workflow_status: Mapped[str] = mapped_column(String(30), default="WAITING_VEHICLE", server_default="WAITING_VEHICLE")
    prepared_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


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
    warranty_id: Mapped[UUID | None] = mapped_column(nullable=True)
    inspection_type: Mapped[str] = mapped_column(String(50))
    status: Mapped[str] = mapped_column(String(20), default="PENDING")
    result: Mapped[str | None] = mapped_column(String(10))
    failure_reason: Mapped[str | None] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class VehicleWarrantyProjection(Base):
    __tablename__ = "vehicle_warranty_projection"
    warranty_id: Mapped[UUID] = mapped_column(primary_key=True)
    vehicle_id: Mapped[UUID] = mapped_column(index=True)
    warranty_status: Mapped[str] = mapped_column(String(20))
    warranty_type: Mapped[str] = mapped_column(String(50))
    start_date: Mapped[date]
    end_date: Mapped[date]
    source_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    synced_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    source_lsn: Mapped[int] = mapped_column(BigInteger)
    source_partition: Mapped[int]
    source_offset: Mapped[int] = mapped_column(BigInteger)
    is_deleted: Mapped[bool] = mapped_column(default=False)


class InspectionReport(Timestamps, Base):
    """One official document per completed inspection, rendered by a Celery worker.

    The row is created in the completion transaction and doubles as the durable task
    intent: the dispatcher publishes PENDING rows to RabbitMQ, so a crash between
    commit and publish can delay a report but never lose it.
    """

    __tablename__ = "inspection_reports"
    __table_args__ = (
        UniqueConstraint("inspection_id", name="inspection_reports_inspection_id_key"),
        UniqueConstraint("task_id", name="inspection_reports_task_id_key"),
        CheckConstraint(
            "status IN ('PENDING','QUEUED','PROCESSING','RETRY_SCHEDULED','GENERATED','FAILED')",
            name="inspection_report_status",
        ),
        CheckConstraint("kind IN ('CERTIFICATE','DEFECT_REPORT')", name="inspection_report_kind"),
        CheckConstraint(
            "(status = 'GENERATED') = (document IS NOT NULL AND sha256 IS NOT NULL AND generated_at IS NOT NULL)",
            name="inspection_report_document",
        ),
        Index("ix_inspection_reports_dispatch", "priority", "created_at", postgresql_where=text("status = 'PENDING'")),
        Index("ix_inspection_reports_open", "status", postgresql_where=text("status <> 'GENERATED'")),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    inspection_id: Mapped[UUID] = mapped_column(ForeignKey("inspections.id"))
    vehicle_id: Mapped[UUID]
    kind: Mapped[str] = mapped_column(String(20))
    # AMQP priority: quorum queues treat 5..255 as high and 0..4 as normal.
    priority: Mapped[int] = mapped_column(SmallInteger)
    status: Mapped[str] = mapped_column(String(20), default="PENDING", server_default="PENDING")
    # Stable Celery task ID across dispatch retries, task retries and redeliveries.
    task_id: Mapped[UUID] = mapped_column(default=uuid4)
    correlation_id: Mapped[str | None] = mapped_column(String(64))
    attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    dispatch_attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    next_dispatch_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, server_default=func.now())
    queued_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    generated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    worker: Mapped[str | None] = mapped_column(String(255))
    last_error: Mapped[str | None] = mapped_column(Text)
    report_number: Mapped[str | None] = mapped_column(String(40))
    sha256: Mapped[str | None] = mapped_column(String(64))
    size_bytes: Mapped[int | None] = mapped_column(Integer)
    document: Mapped[bytes | None] = mapped_column(LargeBinary, deferred=True)
