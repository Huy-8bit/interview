"""Initial vehicle schema and durable messaging tables."""

from platform_common.migration_v1 import downgrade_common, statements, upgrade_common

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    upgrade_common()
    statements("""
CREATE TABLE vehicles (
 id UUID PRIMARY KEY, vin VARCHAR(17) NOT NULL UNIQUE,
 model VARCHAR(100) NOT NULL, manufacturer VARCHAR(100) NOT NULL,
 production_year INTEGER NOT NULL CHECK(production_year BETWEEN 1886 AND 2100),
 owner_name VARCHAR(200) NOT NULL, status VARCHAR(20) NOT NULL CHECK(status IN ('ACTIVE','INACTIVE')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_vehicles_created ON vehicles(created_at,id);
    """)


def downgrade():
    statements("DROP TABLE vehicles;")
    downgrade_common()
