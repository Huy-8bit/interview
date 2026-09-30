import asyncio
import os

from alembic import context
from sqlalchemy import pool
from sqlalchemy.ext.asyncio import create_async_engine

from app.models import repair  # noqa: F401
from platform_common import models  # noqa: F401
from platform_common.db import Base


def migrate(connection):
    context.configure(connection=connection, target_metadata=Base.metadata)
    with context.begin_transaction():
        context.run_migrations()


async def online():
    engine = create_async_engine(os.environ["WRITE_DATABASE_URL"], poolclass=pool.NullPool)
    async with engine.connect() as connection:
        # Concurrent replicas serialize startup migrations in this database.
        await connection.exec_driver_sql("SELECT pg_advisory_lock(72143819)")
        await connection.commit()
        await connection.run_sync(migrate)
        await connection.exec_driver_sql("SELECT pg_advisory_unlock(72143819)")
        await connection.commit()
    await engine.dispose()


if context.is_offline_mode():
    context.configure(
        url=os.environ["WRITE_DATABASE_URL"], target_metadata=Base.metadata, literal_binds=True
    )
    with context.begin_transaction():
        context.run_migrations()
else:
    asyncio.run(online())
