"""Two independent inputs prepare the local inspection workflow."""
from platform_common.migration_v1 import statements

revision = "0002"
down_revision = "0001"
branch_labels = depends_on = None

def upgrade():
    statements("""
ALTER TABLE vehicle_references ADD COLUMN vehicle_payload JSONB;
ALTER TABLE vehicle_references ADD COLUMN source_updated_at TIMESTAMPTZ;
ALTER TABLE vehicle_references ADD COLUMN warranty_id UUID;
ALTER TABLE vehicle_references ADD COLUMN workflow_status VARCHAR(30) NOT NULL DEFAULT 'WAITING_VEHICLE';
ALTER TABLE vehicle_references ADD COLUMN prepared_at TIMESTAMPTZ;
UPDATE vehicle_references SET warranty_seen=false, workflow_status=CASE WHEN vehicle_seen THEN 'WAITING_WARRANTY' ELSE 'WAITING_VEHICLE' END;
ALTER TABLE inspections ADD COLUMN warranty_id UUID;
CREATE TABLE vehicle_warranty_projection (
 warranty_id UUID PRIMARY KEY, vehicle_id UUID NOT NULL, warranty_status VARCHAR(20) NOT NULL, warranty_type VARCHAR(50) NOT NULL,
 start_date DATE NOT NULL, end_date DATE NOT NULL, source_updated_at TIMESTAMPTZ NOT NULL, synced_at TIMESTAMPTZ NOT NULL,
 source_lsn BIGINT NOT NULL, source_partition INTEGER NOT NULL, source_offset BIGINT NOT NULL, is_deleted BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX ix_vehicle_warranty_projection_vehicle_id ON vehicle_warranty_projection(vehicle_id);
""")

def downgrade():
    statements("""
DROP TABLE vehicle_warranty_projection;
ALTER TABLE inspections DROP COLUMN warranty_id;
ALTER TABLE vehicle_references DROP COLUMN vehicle_payload, DROP COLUMN source_updated_at, DROP COLUMN warranty_id, DROP COLUMN workflow_status, DROP COLUMN prepared_at;
""")
