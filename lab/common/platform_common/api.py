import asyncio
import logging
import time
from contextlib import asynccontextmanager
from uuid import UUID, uuid4

from aiokafka.admin import AIOKafkaAdminClient
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError, IntegrityError
from sqlalchemy.exc import TimeoutError as PoolTimeout

from platform_common import context
from platform_common.config import Settings
from platform_common.errors import DomainError, TransientError
from platform_common.logging import configure_logging
from platform_common.runtime import Runtime

log = logging.getLogger(__name__)


def get_runtime(request: Request) -> Runtime:
    return request.app.state.runtime


def identifier(value):
    try:
        return str(UUID(value))
    except (TypeError, ValueError, AttributeError):
        return str(uuid4())


def create_app(router, *, handlers=None, extra_workers=(), settings=None):
    settings = settings or Settings()
    configure_logging(settings.service_name, settings.log_level)

    @asynccontextmanager
    async def lifespan(app):
        runtime = Runtime(settings)
        app.state.runtime = runtime
        await runtime.start(handlers, extra_workers)
        try:
            yield
        finally:
            await runtime.close()

    app = FastAPI(title=settings.service_name, version="1.0.0", lifespan=lifespan)
    app.include_router(router)

    @app.middleware("http")
    async def request_context(request, call_next):
        rid = identifier(request.headers.get("X-Request-ID"))
        cid = identifier(request.headers.get("X-Correlation-ID") or rid)
        rt, ct = context.request_id.set(rid), context.correlation_id.set(cid)
        started = time.monotonic()
        try:
            response = await call_next(request)
            response.headers["X-Request-ID"] = rid
            response.headers["X-Correlation-ID"] = cid
            log.info(
                "http_request",
                extra={
                    "fields": {
                        "method": request.method,
                        "path": request.url.path,
                        "status": response.status_code,
                        "duration_ms": round((time.monotonic() - started) * 1000, 2),
                    }
                },
            )
            return response
        finally:
            context.request_id.reset(rt)
            context.correlation_id.reset(ct)

    def error(status, code, message):
        return JSONResponse(
            status_code=status,
            content={
                "error": {
                    "code": code,
                    "message": message,
                    "request_id": context.request_id.get(),
                }
            },
            headers={"Retry-After": "2"} if status == 503 else None,
        )

    @app.exception_handler(DomainError)
    async def domain_error(request, exc):
        return error(exc.status, exc.code, str(exc))

    @app.exception_handler(TransientError)
    async def transient_error(request, exc):
        return error(503, "dependency_unavailable", str(exc))

    @app.exception_handler(IntegrityError)
    async def integrity_error(request, exc):
        return error(
            409, "constraint_conflict", "Unique value, reference or business constraint violated"
        )

    @app.exception_handler(PoolTimeout)
    @app.exception_handler(DBAPIError)
    @app.exception_handler(OSError)
    async def database_error(request, exc):
        log.error("database_unavailable", extra={"fields": {"error_type": type(exc).__name__}})
        return error(
            503,
            "database_unavailable",
            "Database unavailable or connection pool exhausted; retry later",
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        return error(422, "validation_error", str(exc))

    @app.exception_handler(Exception)
    async def unexpected_error(request, exc):
        log.exception("unexpected_error", exc_info=exc)
        return error(500, "internal_error", "Unexpected internal error")

    @app.get("/health", tags=["operations"])
    async def health(request: Request):
        return {
            "status": "alive",
            "service": settings.service_name,
            "instance_id": get_runtime(request).instance_id,
        }

    @app.get("/ready", tags=["operations"])
    async def ready(request: Request):
        runtime = get_runtime(request)

        async def db_check():
            async with runtime.sessions() as session:
                await session.execute(text("SELECT 1"))

        async def kafka_check():
            admin = AIOKafkaAdminClient(
                bootstrap_servers=settings.kafka_bootstrap_servers, request_timeout_ms=2000
            )
            try:
                await admin.start()
                await admin.describe_cluster()
            finally:
                await admin.close()

        async def redis_check():
            info = await runtime.redis.cluster_info()
            if info.get("cluster_state") != "ok" or int(info.get("cluster_slots_ok", 0)) != 16384:
                raise RuntimeError("Redis Cluster slots unavailable")

        async def check(fn):
            try:
                async with asyncio.timeout(3):
                    await fn()
                return "ok"
            except Exception:
                return "unavailable"

        results = await asyncio.gather(
            check(db_check), check(redis_check), check(kafka_check)
        )
        checks = dict(zip(("postgres", "redis", "kafka"), results, strict=True))
        checks["workers"] = "ok" if all(not task.done() for task in runtime.tasks) else "failed"
        ok = all(value == "ok" for value in checks.values())
        return JSONResponse(
            status_code=200 if ok else 503,
            content={"status": "ready" if ok else "degraded", "checks": checks},
        )

    if settings.lab_mode:
        from platform_common.lab import router as lab_router

        app.include_router(lab_router)
    return app
