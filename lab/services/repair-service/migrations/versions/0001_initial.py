"""Initial repair schema and durable messaging tables."""

from platform_common.migration_v1 import downgrade_common, statements, upgrade_common

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    upgrade_common()
    statements("""
CREATE TABLE repair_requests (
 id UUID PRIMARY KEY, vehicle_id UUID NOT NULL, inspection_id UUID NOT NULL UNIQUE,
 warranty_covered BOOLEAN NOT NULL, status VARCHAR(20) NOT NULL,
 description TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT ck_repair_requests_repair_status CHECK(status IN ('OPEN','IN_PROGRESS','COMPLETED','CANCELLED'))
);
CREATE INDEX ix_repairs_vehicle_created ON repair_requests(vehicle_id,created_at);
CREATE TABLE notifications (
 id UUID PRIMARY KEY, vehicle_id UUID NOT NULL, repair_id UUID NOT NULL REFERENCES repair_requests(id),
 channel VARCHAR(20) NOT NULL, message TEXT NOT NULL, status VARCHAR(20) NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT uq_notification_repair_channel UNIQUE(repair_id,channel)
);
    """)


def downgrade():
    statements("DROP TABLE notifications; DROP TABLE repair_requests;")
    downgrade_common()
