"""Initial inspection schema and durable messaging tables."""

from platform_common.migration_v1 import downgrade_common, statements, upgrade_common

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    upgrade_common()
    statements("""
CREATE TABLE vehicle_references (
 vehicle_id UUID PRIMARY KEY, vehicle_seen BOOLEAN NOT NULL, warranty_seen BOOLEAN NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE inspections (
 id UUID PRIMARY KEY, vehicle_id UUID NOT NULL, inspection_type VARCHAR(50) NOT NULL,
 status VARCHAR(20) NOT NULL, result VARCHAR(10), failure_reason TEXT, notes TEXT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), completed_at TIMESTAMPTZ,
 CONSTRAINT ck_inspections_inspection_status CHECK(status IN ('PENDING','IN_PROGRESS','COMPLETED')),
 CONSTRAINT ck_inspections_inspection_completion CHECK(
  (status = 'COMPLETED' AND result IN ('PASS','FAIL') AND result IS NOT NULL AND completed_at IS NOT NULL)
  OR (status != 'COMPLETED' AND result IS NULL AND completed_at IS NULL)),
 CONSTRAINT ck_inspections_inspection_failure_reason CHECK(
  (result = 'FAIL' AND failure_reason IS NOT NULL AND length(trim(failure_reason)) > 0)
  OR ((result IS NULL OR result = 'PASS') AND failure_reason IS NULL))
);
CREATE INDEX ix_inspections_vehicle_created ON inspections(vehicle_id,created_at);
    """)


def downgrade():
    statements("DROP TABLE inspections; DROP TABLE vehicle_references;")
    downgrade_common()
