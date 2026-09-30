import json
from uuid import uuid4

import httpx
import pytest_asyncio

from app.models import vehicle  # noqa: F401
from platform_common.testing import runtime  # noqa: F401


@pytest_asyncio.fixture(autouse=True)
async def isolate_warranty_rest(runtime):  # noqa: F811
    await runtime.http.aclose()
    def handle(request):
        assert request.url.path == "/internal/warranties"
        return httpx.Response(201, json={"id": str(uuid4()), "vehicle_id": json.loads(request.content)["vehicle_id"], "warranty_type": "DEFAULT"})
    runtime.http = httpx.AsyncClient(transport=httpx.MockTransport(handle))
