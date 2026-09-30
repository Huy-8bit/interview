import asyncio
import logging
from datetime import datetime
from uuid import UUID

import httpx
from pydantic import BaseModel, StrictBool, ValidationError

from platform_common.errors import TransientError
from platform_common.http_client import request

log = logging.getLogger(__name__)


class CoverageResponse(BaseModel):
    vehicle_id: UUID
    covered: StrictBool
    warranty_id: UUID | None
    checked_at: datetime


async def check_coverage(runtime, vehicle_id) -> CoverageResponse:
    settings = runtime.settings
    for attempt in range(settings.http_retries + 1):
        try:
            runtime.metrics.business["warranty_coverage_check_total"].inc()
            response = await request(runtime, "warranty-service", "GET",
                f"/internal/warranties/vehicle/{vehicle_id}/coverage",
                "/internal/warranties/vehicle/{vehicle_id}/coverage")
            # 404 means the vehicle's first event may not have arrived yet.
            if (
                response.status_code == 404
                or response.status_code == 429
                or response.status_code >= 500
            ):
                raise TransientError(f"Warranty dependency returned {response.status_code}")
            response.raise_for_status()
            coverage = CoverageResponse.model_validate(response.json())
            if coverage.vehicle_id != vehicle_id:
                raise TransientError("Warranty response vehicle mismatch")
            return coverage
        except (httpx.HTTPError, ValueError, ValidationError, TransientError) as exc:
            log.warning(
                "warranty_http_retry",
                extra={"fields": {"attempt": attempt + 1, "error_type": type(exc).__name__}},
            )
            if attempt == settings.http_retries:
                raise TransientError(
                    "Warranty lookup unavailable; coverage remains unknown and no repair was committed"
                ) from exc
            await asyncio.sleep(0.2 * 2**attempt)
    raise AssertionError("unreachable")
