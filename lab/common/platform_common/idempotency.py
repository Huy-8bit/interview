import hashlib
import json

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert

from platform_common.errors import DomainError
from platform_common.models import IdempotencyRecord


def fingerprint(value) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), default=str).encode()
    ).hexdigest()


def verify(actual: str, expected: str):
    if actual != expected:
        raise DomainError(
            409,
            "idempotency_key_reused",
            "Idempotency-Key was already used with a different request",
        )


async def execute_idempotent(runtime, scope: str, key: str, payload: dict, action):
    """The durable reservation, resource, outbox and response share one DB transaction."""
    key_hash = hashlib.sha256(key.encode()).hexdigest()
    digest = fingerprint(payload)
    redis_key = f"idem:{runtime.settings.service_name}:{scope}:{key_hash}"
    cached = await runtime.cache.get_json(redis_key)
    if cached and cached.get("state") == "completed":
        verify(cached["request_hash"], digest)
        return cached["response"]
    async with runtime.cache.lock(
        f"idem:{scope}:{key_hash}", contention_is_error=False
    ) as acquired:
        if acquired:
            await runtime.cache.set_json(
                redis_key,
                {"state": "processing", "request_hash": digest},
                runtime.settings.lock_timeout,
            )
        async with runtime.sessions.begin() as session:
            reserved = await session.scalar(
                insert(IdempotencyRecord)
                .values(
                    scope=scope,
                    key_hash=key_hash,
                    request_hash=digest,
                )
                .on_conflict_do_nothing(index_elements=["scope", "key_hash"])
                .returning(IdempotencyRecord.key_hash)
            )
            if reserved:
                response = await action(session)
                await session.execute(
                    update(IdempotencyRecord)
                    .where(
                        IdempotencyRecord.scope == scope,
                        IdempotencyRecord.key_hash == key_hash,
                    )
                    .values(response=response)
                )
            else:
                record = await session.scalar(
                    select(IdempotencyRecord).where(
                        IdempotencyRecord.scope == scope,
                        IdempotencyRecord.key_hash == key_hash,
                    )
                )
                verify(record.request_hash, digest)
                response = record.response
        await runtime.cache.set_json(
            redis_key,
            {"state": "completed", "request_hash": digest, "response": response},
            runtime.settings.idempotency_ttl,
        )
        return response
