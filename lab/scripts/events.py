"""Run inside the producing service; only reads that service's own database."""

import argparse
import asyncio
import json
from uuid import UUID

from sqlalchemy import select

from platform_common.config import Settings
from platform_common.models import OutboxEvent
from platform_common.runtime import Runtime


async def main(args):
    runtime = Runtime(Settings())
    try:
        if args.command == "list":
            async with runtime.sessions() as session:
                rows = (
                    await session.scalars(
                        select(OutboxEvent).order_by(OutboxEvent.id.desc()).limit(20)
                    )
                ).all()
                print(
                    json.dumps(
                        [
                            {
                                "event_id": str(r.event_id),
                                "type": r.event_type,
                                "status": r.status,
                                "attempts": r.attempts,
                                "aggregate_id": r.aggregate_id,
                            }
                            for r in rows
                        ],
                        indent=2,
                    )
                )
        else:
            async with runtime.sessions() as session:
                row = await session.scalar(
                    select(OutboxEvent).where(OutboxEvent.event_id == UUID(args.event_id))
                )
                if row is None:
                    raise SystemExit("Event not found in this service's outbox")
            for index in range(args.count):
                if args.scatter:
                    await runtime.publisher.start()
                    partitions = sorted(await runtime.publisher.producer.partitions_for(row.topic))
                    await runtime.publisher.producer.send_and_wait(
                        row.topic,
                        key=row.aggregate_id.encode(),
                        value=json.dumps(row.payload).encode(),
                        partition=partitions[index % len(partitions)],
                    )
                else:
                    await runtime.publisher.publish(row.topic, row.aggregate_id, row.payload)
            print(f"Republished {args.count} copies with the SAME event_id: {row.event_id}")
    finally:
        await runtime.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list")
    duplicate = commands.add_parser("duplicate")
    duplicate.add_argument("event_id")
    duplicate.add_argument("--count", type=int, default=2)
    duplicate.add_argument(
        "--scatter",
        action="store_true",
        help="Deliberately send duplicate event IDs to different partitions",
    )
    asyncio.run(main(parser.parse_args()))
