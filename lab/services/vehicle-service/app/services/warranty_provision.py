"""Durable REST delivery. A lost HTTP response is safe: B deduplicates by vehicle/type."""
import asyncio
import logging
from datetime import timedelta
from uuid import UUID

from pydantic import BaseModel
from sqlalchemy import func, select

from app.models.vehicle import WarrantyProvisionRequest
from platform_common import context
from platform_common.db import utcnow
from platform_common.http_client import request
from platform_common.outbox import backoff

log = logging.getLogger(__name__)


class ProvisionResult(BaseModel):
    id: UUID
    vehicle_id: UUID
    warranty_type: str


async def deliver_pending(runtime, vehicle_id=None):
    async with runtime.sessions.begin() as session:
        query = select(WarrantyProvisionRequest).where(WarrantyProvisionRequest.status == "PENDING", WarrantyProvisionRequest.next_attempt_at <= utcnow())
        if vehicle_id:
            query = query.where(WarrantyProvisionRequest.vehicle_id == vehicle_id)
        row = await session.scalar(query.order_by(WarrantyProvisionRequest.created_at).limit(1).with_for_update(skip_locked=True))
        if row is None:
            return False
        token = context.correlation_id.set(row.correlation_id)
        try:
            response = await request(runtime, "warranty-service", "POST", "/internal/warranties", "/internal/warranties",
                                     json={"vehicle_id": str(row.vehicle_id), "vehicle_created_at": row.created_at.isoformat()},
                                     headers={"Idempotency-Key": f"vehicle-warranty:{row.vehicle_id}"})
            response.raise_for_status()
            result = ProvisionResult.model_validate(response.json())
            if result.vehicle_id != row.vehicle_id or result.warranty_type != "DEFAULT":
                raise ValueError("Warranty response does not match provision request")
            row.status, row.warranty_id, row.last_error = "DELIVERED", result.id, None
            log.info("warranty_provision_delivered", extra={"fields": {"vehicle_id": str(row.vehicle_id), "warranty_id": str(result.id)}})
        except Exception as exc:
            row.attempts += 1
            row.last_error = type(exc).__name__  # Do not persist URLs/credentials from transport errors.
            row.next_attempt_at = utcnow() + timedelta(seconds=min(60, backoff(min(row.attempts, 6), 0.5)))
            runtime.metrics.rest_failures.inc()
            log.warning("warranty_provision_pending", extra={"fields": {"vehicle_id": str(row.vehicle_id), "attempt": row.attempts, "error_type": type(exc).__name__}})
        finally:
            context.correlation_id.reset(token)
    return True


async def provision_loop(runtime):
    while True:
        try:
            async with runtime.sessions() as session:
                pending = await session.scalar(select(func.count()).select_from(WarrantyProvisionRequest).where(WarrantyProvisionRequest.status == "PENDING"))
            runtime.metrics.rest_pending.set(pending)
            if await deliver_pending(runtime):
                continue
        except Exception:
            log.exception("warranty_provision_worker_retry")
        await asyncio.sleep(1)
