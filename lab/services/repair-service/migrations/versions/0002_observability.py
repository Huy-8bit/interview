"""Persist correlation across CDC / coverage ID across REST."""
import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = depends_on = None

def upgrade():
    op.add_column("repair_requests", sa.Column("warranty_id", sa.Uuid(), nullable=True))

def downgrade():
    op.drop_column("repair_requests", "warranty_id")
