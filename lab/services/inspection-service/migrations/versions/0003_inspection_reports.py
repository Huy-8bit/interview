"""Inspection reports rendered asynchronously by Celery workers over RabbitMQ.

Historic inspections get no report row: issuing reports starts with this release.
"""
from platform_common.migration_v1 import statements

revision = "0003"
down_revision = "0002"
branch_labels = depends_on = None


def upgrade():
    statements("""
CREATE TABLE inspection_reports (
 id UUID PRIMARY KEY, inspection_id UUID NOT NULL REFERENCES inspections(id), vehicle_id UUID NOT NULL,
 kind VARCHAR(20) NOT NULL, priority SMALLINT NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
 task_id UUID NOT NULL, correlation_id VARCHAR(64), attempts INTEGER NOT NULL DEFAULT 0,
 dispatch_attempts INTEGER NOT NULL DEFAULT 0, next_dispatch_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 queued_at TIMESTAMPTZ, started_at TIMESTAMPTZ, generated_at TIMESTAMPTZ, failed_at TIMESTAMPTZ,
 worker VARCHAR(255), last_error TEXT, report_number VARCHAR(40), sha256 VARCHAR(64), size_bytes INTEGER, document BYTEA,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT inspection_reports_inspection_id_key UNIQUE (inspection_id),
 CONSTRAINT inspection_reports_task_id_key UNIQUE (task_id),
 CONSTRAINT ck_inspection_reports_inspection_report_status CHECK (status IN ('PENDING','QUEUED','PROCESSING','RETRY_SCHEDULED','GENERATED','FAILED')),
 CONSTRAINT ck_inspection_reports_inspection_report_kind CHECK (kind IN ('CERTIFICATE','DEFECT_REPORT')),
 CONSTRAINT ck_inspection_reports_inspection_report_document CHECK ((status = 'GENERATED') = (document IS NOT NULL AND sha256 IS NOT NULL AND generated_at IS NOT NULL))
);
CREATE INDEX ix_inspection_reports_dispatch ON inspection_reports (priority, created_at) WHERE status = 'PENDING';
CREATE INDEX ix_inspection_reports_open ON inspection_reports (status) WHERE status <> 'GENERATED'
""")


def downgrade():
    statements("DROP TABLE inspection_reports")
