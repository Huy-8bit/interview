"""Mark synthetic vehicles so API deletion cannot target ordinary records."""

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("ALTER TABLE vehicles ADD COLUMN simulation_run_id UUID NULL")


def downgrade():
    op.execute("ALTER TABLE vehicles DROP COLUMN simulation_run_id")
