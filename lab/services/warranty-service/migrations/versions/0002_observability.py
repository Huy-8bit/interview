"""Persist correlation across CDC / coverage ID across REST."""
import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = depends_on = None

def upgrade():
    op.add_column("warranties", sa.Column("correlation_id", sa.String(128), nullable=True))

def downgrade():
    op.drop_column("warranties", "correlation_id")
