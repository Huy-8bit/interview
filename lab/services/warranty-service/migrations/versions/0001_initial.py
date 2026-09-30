"""Initial warranty schema and durable messaging tables."""

from platform_common.migration_v1 import downgrade_common, statements, upgrade_common

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    upgrade_common()
    statements("""
CREATE TABLE warranties (
 id UUID PRIMARY KEY, vehicle_id UUID NOT NULL, warranty_type VARCHAR(50) NOT NULL,
 start_date DATE NOT NULL, end_date DATE NOT NULL, status VARCHAR(20) NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT uq_warranty_vehicle_type UNIQUE(vehicle_id,warranty_type),
 CONSTRAINT ck_warranties_warranty_dates CHECK(end_date >= start_date),
 CONSTRAINT ck_warranties_warranty_status CHECK(status IN ('PENDING','ACTIVE','EXPIRED'))
);
CREATE INDEX ix_warranties_coverage ON warranties(vehicle_id,status,start_date,end_date);
CREATE INDEX ix_warranties_expiry ON warranties(status,end_date);
    """)


def downgrade():
    statements("DROP TABLE warranties;")
    downgrade_common()
