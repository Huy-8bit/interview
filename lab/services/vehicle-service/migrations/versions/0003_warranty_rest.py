"""Durable REST provision command, committed with vehicle and domain outbox."""
from platform_common.migration_v1 import statements

revision = "0003"
down_revision = "0002"
branch_labels = depends_on = None

def upgrade():
    statements("""
CREATE TABLE warranty_provision_requests (
 vehicle_id UUID PRIMARY KEY, correlation_id VARCHAR(128) NOT NULL,
 status VARCHAR(20) NOT NULL DEFAULT 'PENDING', attempts INTEGER NOT NULL DEFAULT 0,
 warranty_id UUID, last_error VARCHAR(100), next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_warranty_provision_requests_status ON warranty_provision_requests(status);
""")

def downgrade():
    statements("DROP TABLE warranty_provision_requests;")
