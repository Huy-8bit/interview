"""Repair tickets reference the defect report rendered by Inspection workers."""
import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = depends_on = None


def upgrade():
    op.add_column("repair_requests", sa.Column("defect_report_number", sa.String(40), nullable=True))
    op.add_column("repair_requests", sa.Column("defect_report_sha256", sa.String(64), nullable=True))
    op.add_column("repair_requests", sa.Column("defect_report_generated_at", sa.DateTime(timezone=True), nullable=True))


def downgrade():
    for column in ("defect_report_generated_at", "defect_report_sha256", "defect_report_number"):
        op.drop_column("repair_requests", column)
