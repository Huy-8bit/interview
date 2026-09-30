"""Operator tool for the report queue: status, DLQ inspection/replay and drill faults.

Run inside inspection-service (it has RabbitMQ and inspection_db credentials):
  docker compose exec inspection-service python -m app.reports.cli status
  docker compose exec inspection-service python -m app.reports.cli dlq
  docker compose exec inspection-service python -m app.reports.cli replay --limit 10
  docker compose exec inspection-service python -m app.reports.cli submit --fault transient
"""
import argparse
import ast
import json
import time
from datetime import UTC, datetime
from urllib.parse import quote, urlsplit
from uuid import UUID, uuid4

import amqp
import httpx
from sqlalchemy import select

from app.models.inspection import InspectionReport
from app.reports.celery_app import (
    DLQ,
    EXCHANGE,
    HIGH_PRIORITY,
    NORMAL_PRIORITY,
    QUEUE,
    ROUTING_KEY,
    TASK_NAME,
    celery_app,
    settings,
)

URLS = [urlsplit(url) for url in settings.rabbitmq_urls.split(";")]
AUTH = (URLS[0].username, URLS[0].password)


def management(method, path, **kwargs):
    last = None
    for url in URLS:
        try:
            response = httpx.request(method, f"http://{url.hostname}:15672/api{path}", auth=AUTH, timeout=10, **kwargs)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as exc:
            last = exc
    raise SystemExit(f"Management API unreachable: {last}")


def status(_):
    nodes = management("GET", "/nodes")
    queues = management("GET", "/queues/%2F")
    print(json.dumps({
        "nodes": {n["name"]: "running" if n.get("running") else "DOWN" for n in nodes},
        "queues": {
            q["name"]: {
                "ready": q.get("messages_ready", 0), "unacked": q.get("messages_unacknowledged", 0),
                "consumers": q.get("consumers", 0), "leader": q.get("leader"), "members": sorted(q.get("members", [])),
                "online": sorted(q.get("online", [])),
            }
            for q in queues if q["name"] in (QUEUE, DLQ)
        },
    }, indent=2))


def kwargs_of(headers, payload):
    try:
        return json.loads(payload)[1]
    except (ValueError, IndexError, TypeError):
        return ast.literal_eval(headers.get("kwargsrepr") or "{}")


def last_errors(ids):
    from app.reports.tasks import sessions

    valid = [UUID(i) for i in ids if i]
    if not valid:
        return {}
    with sessions()() as session:
        rows = session.execute(select(InspectionReport.inspection_id, InspectionReport.status, InspectionReport.last_error)
                               .where(InspectionReport.inspection_id.in_(valid))).all()
    return {str(row.inspection_id): {"report_status": row.status, "last_error": row.last_error} for row in rows}


def dlq(args):
    # ack_requeue_true returns each message to the DLQ; its policy has no delivery limit.
    messages = management("POST", f"/queues/%2F/{quote(DLQ, safe='')}/get",
                          json={"count": args.limit, "ackmode": "ack_requeue_true", "encoding": "auto"})
    records = []
    for message in messages:
        headers = message["properties"].get("headers", {})
        death = next((d for d in headers.get("x-death", []) if d.get("queue") == QUEUE), {})
        kwargs = kwargs_of(headers, message["payload"])
        records.append({
            "task_id": headers.get("id"), "task_type": headers.get("task"),
            "inspection_id": kwargs.get("inspection_id"), "fault": kwargs.get("fault"),
            "retries": headers.get("retries"), "priority": message["properties"].get("priority"),
            "dead_letter_reason": death.get("reason") or headers.get("x-last-death-reason"),
            "dead_lettered_at": datetime.fromtimestamp(death["time"], UTC).isoformat() if death.get("time") else None,
            "delivery_count": headers.get("x-delivery-count"),
        })
    errors = last_errors([r["inspection_id"] for r in records])
    for record in records:
        record.update(errors.get(record["inspection_id"], {"report_status": None, "last_error": "no report row (synthetic drill task)"}))
    print(json.dumps({"dlq": DLQ, "shown": len(records), "records": records}, indent=2))


def replay(args):
    """Move DLQ messages back to the work queue with a fresh retry budget."""
    from app.reports.tasks import sessions

    url = URLS[0]
    connection = amqp.Connection(host=f"{url.hostname}:{url.port or 5672}", userid=url.username, password=url.password,
                                 virtual_host="/", confirm_publish=True, connect_timeout=5)
    connection.connect()
    channel, replayed = connection.channel(), []
    try:
        for _ in range(args.limit):
            message = channel.basic_get(DLQ, no_ack=False)
            if message is None:
                break
            properties = dict(message.properties)
            headers = dict(properties.pop("application_headers", {}) or {})
            headers.update({"retries": 0, "x-replayed-at": datetime.now(UTC).isoformat()})
            # Confirmed publish first, then ACK: a crash in between duplicates, never loses.
            channel.basic_publish(amqp.Message(message.body, application_headers=headers, **properties),
                                  exchange=EXCHANGE.name, routing_key=ROUTING_KEY)
            channel.basic_ack(message.delivery_tag)
            replayed.append(kwargs_of(headers, message.body).get("inspection_id"))
    finally:
        connection.close()
    ids = [UUID(i) for i in replayed if i]
    if ids:
        with sessions().begin() as session:
            for row in session.scalars(select(InspectionReport).where(InspectionReport.inspection_id.in_(ids), InspectionReport.status == "FAILED")):
                row.status, row.last_error = "QUEUED", f"replayed from DLQ at {datetime.now(UTC).isoformat()}; previous: {row.last_error}"
    print(json.dumps({"replayed": len(replayed), "inspection_ids": replayed}, indent=2))


def submit(args):
    inspection_id = args.inspection_id or str(uuid4())
    result = celery_app.send_task(TASK_NAME, kwargs={"inspection_id": inspection_id, "fault": args.fault, "submitted_at": time.time()},
                                  priority=HIGH_PRIORITY if args.high else NORMAL_PRIORITY)
    print(json.dumps({"task_id": result.id, "inspection_id": inspection_id, "fault": args.fault,
                      "expect": {"transient": "3 retries via celery_delayed_* then DLQ", "hang": "soft time limit -> retries -> DLQ",
                                 "stuck": "hard time limit kills the child -> redelivery -> delivery-limit -> DLQ",
                                 None: "no report row -> permanent error -> DLQ without retry"}.get(args.fault, "slow task")}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", help="Cluster nodes, work queue and DLQ depth, leader and members").set_defaults(run=status)
    listing = commands.add_parser("dlq", help="Show dead-lettered tasks with the failure recorded in inspection_db")
    listing.add_argument("--limit", type=int, default=20)
    listing.set_defaults(run=dlq)
    moving = commands.add_parser("replay", help="Republish DLQ tasks to the work queue with retries reset")
    moving.add_argument("--limit", type=int, default=10)
    moving.set_defaults(run=replay)
    drill = commands.add_parser("submit", help="Publish a drill task; without --fault and --inspection-id it fails permanently")
    drill.add_argument("--fault", choices=["transient", "hang", "stuck"], help="Injected failure mode (or slow:SECONDS)")
    drill.add_argument("--slow", type=float, help="Sleep this many seconds inside the task")
    drill.add_argument("--inspection-id")
    drill.add_argument("--high", action="store_true", help="Publish with high priority")
    drill.set_defaults(run=submit)
    parsed = parser.parse_args()
    if getattr(parsed, "slow", None):
        parsed.fault = f"slow:{parsed.slow}"
    parsed.run(parsed)
