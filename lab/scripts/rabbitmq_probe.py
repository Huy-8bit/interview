"""Observe RabbitMQ + Celery report processing for drills and the backlog demo.

Reads three independent sources so a claim never rests on one component's opinion:
the RabbitMQ management API (cluster, leader, depth), Prometheus (worker counters)
and inspection_db (report rows and outbox events, i.e. the business effect).
"""
import argparse
import asyncio
import json
import os
import time
from pathlib import Path
from urllib.parse import quote

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

NODES = ["rabbitmq-1", "rabbitmq-2", "rabbitmq-3"]
AUTH = (os.getenv("RABBITMQ_USER", "lab"), os.getenv("RABBITMQ_PASSWORD", "lab_rabbitmq_password"))
PROM = os.getenv("PROMETHEUS_URL", "http://prometheus:9090")
WORK, DLQ = "inspection.report.generate", "inspection.report.dlq"


def management(path):
    last = None
    for node in NODES:
        try:
            response = httpx.get(f"http://{node}:15672/api{path}", auth=AUTH, timeout=5)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as exc:
            last = exc
    raise RuntimeError(f"No management API reachable: {last}")


def prom(expression):
    rows = httpx.get(PROM + "/api/v1/query", params={"query": expression}, timeout=10).json()["data"]["result"]
    return {json.dumps(r["metric"], sort_keys=True): float(r["value"][1]) for r in rows}


def prom_value(expression):
    return sum(prom(expression).values())


async def db(sql, **params):
    engine = create_async_engine(os.environ["INSPECTION_DATABASE_URL"])
    try:
        async with engine.connect() as connection:
            return [dict(row._mapping) for row in (await connection.execute(text(sql), params)).all()]
    finally:
        await engine.dispose()


def queue(name):
    q = management(f"/queues/%2F/{quote(name, safe='')}")
    return {"ready": q.get("messages_ready", 0), "unacked": q.get("messages_unacknowledged", 0), "consumers": q.get("consumers", 0),
            "leader": q.get("leader"), "members": sorted(q.get("members", [])), "online": sorted(q.get("online", []))}


def snapshot():
    nodes = management("/nodes")
    reports = asyncio.run(db("SELECT status, count(*) AS n FROM inspection_reports GROUP BY status"))
    return {
        "at": time.time(),
        "nodes": {n["name"]: bool(n.get("running")) for n in nodes},
        "work": queue(WORK), "dlq": queue(DLQ),
        "generated_total": prom_value('sum(background_tasks_completed_total{outcome="generated"})'),
        "duplicates_total": prom_value('sum(background_tasks_completed_total{outcome="duplicate"})'),
        "redelivered_total": prom_value("sum(background_tasks_redelivered_total)"),
        # Broker-side counter: survives the worker restarts that per-process counters do not.
        "broker_redelivered_total": prom_value('sum(rabbitmq_global_messages_redelivered_total{queue_type="rabbit_quorum_queue"})'),
        "retried_total": prom_value("sum(background_tasks_retried_total)"),
        "failed_total": prom_value("sum(background_tasks_failed_total)"),
        "workers_online": prom_value('count(up{job="report-worker"} == 1)'),
        # Business truth: survives worker restarts, unlike per-process counters.
        "generated_rows": sum(r["n"] for r in reports if r["status"] == "GENERATED"),
        "open_reports": {r["status"]: r["n"] for r in reports if r["status"] != "GENERATED"},
    }


def write(path, value):
    if path:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_text(json.dumps(value, indent=2) + "\n")
    print(json.dumps(value, indent=2 if not path else None)[:4000], flush=True)


def cmd_snapshot(args):
    write(args.output, snapshot())


def cmd_sample(args):
    """Queue depth and completions over time; throughput from DB-independent counters."""
    samples, deadline = [], time.monotonic() + args.duration
    while True:
        try:
            s = snapshot()
            samples.append(s)
            print(f"[{args.label}] t={len(samples) * args.interval:>4}s depth={s['work']['ready'] + s['work']['unacked']:>5} "
                  f"ready={s['work']['ready']:>5} unacked={s['work']['unacked']:>3} consumers={s['work']['consumers']} "
                  f"workers={s['workers_online']:.0f} generated_rows={s['generated_rows']}", flush=True)
        except (RuntimeError, httpx.HTTPError) as exc:
            print(f"[{args.label}] sample failed: {exc}", flush=True)
        if time.monotonic() >= deadline:
            break
        time.sleep(args.interval)
    first, last = samples[0], samples[-1]
    elapsed = last["at"] - first["at"]
    result = {
        "label": args.label, "samples": samples, "elapsed_seconds": round(elapsed, 1),
        "depth_start": first["work"]["ready"] + first["work"]["unacked"],
        "depth_end": last["work"]["ready"] + last["work"]["unacked"],
        "depth_max": max(s["work"]["ready"] + s["work"]["unacked"] for s in samples),
        "throughput_per_second": round((last["generated_rows"] - first["generated_rows"]) / elapsed, 2) if elapsed else 0,
        "queue_wait_p95_by_priority": prom('histogram_quantile(0.95,sum by(le,priority)(rate(background_task_queue_wait_seconds_bucket[2m])))'),
    }
    write(args.output, result)


def cmd_wait(args):
    """Poll until a condition on the work queue or a report row holds."""
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        s = snapshot()
        work = s["work"]
        checks = {
            "leader-changed": lambda: work["leader"] and work["leader"] != args.value,
            "online": lambda: len(work["online"]) == int(args.value),
            "consumers": lambda: work["consumers"] == int(args.value),
            "processing": lambda: bool(asyncio.run(db("SELECT 1 FROM inspection_reports WHERE status = 'PROCESSING' LIMIT 1"))),
            "dlq": lambda: s["dlq"]["ready"] >= int(args.value),
            "drained": lambda: work["ready"] <= int(args.value),
            "generated-above": lambda: s["generated_rows"] > float(args.value),
        }
        done = checks[args.condition]()
        if done:
            write(args.output, {"condition": args.condition, "value": args.value, "snapshot": s})
            return
        time.sleep(1)
    raise SystemExit(f"Timed out waiting for {args.condition}={args.value}: {json.dumps(snapshot())[:1500]}")


def cmd_processing(args):
    rows = asyncio.run(db("SELECT inspection_id::text AS inspection_id, task_id::text AS task_id, worker, attempts FROM inspection_reports "
                          "WHERE status = 'PROCESSING' ORDER BY started_at LIMIT 1"))
    if not rows:
        raise SystemExit("No report is PROCESSING")
    write(args.output, rows[0])


def cmd_report(args):
    """Idempotency proof for one inspection: report row and number of outbox events."""
    deadline = time.monotonic() + args.timeout
    while True:
        rows = asyncio.run(db(
            "SELECT r.status, r.attempts, r.worker, r.task_id::text AS task_id, r.sha256, r.last_error, "
            "(SELECT count(*) FROM outbox_events o WHERE o.event_type = 'inspection.report.generated' "
            " AND o.payload->'data'->>'inspection_id' = :id) AS events "
            "FROM inspection_reports r WHERE r.inspection_id = CAST(:id AS uuid)", id=args.inspection_id))
        if rows and rows[0]["status"] == args.status or time.monotonic() > deadline:
            break
        time.sleep(1)
    if not rows or rows[0]["status"] != args.status:
        raise SystemExit(f"Report for {args.inspection_id} is not {args.status}: {rows}")
    write(args.output, {"inspection_id": args.inspection_id, **rows[0]})


def cmd_verify_backlog(args):
    growing, draining = (json.loads(Path(p).read_text()) for p in (args.growing, args.draining))
    checks = {
        "backlog grew with too few workers": growing["depth_end"] >= growing["depth_start"] + args.min_growth,
        "backlog shrank after scaling": draining["depth_end"] < draining["depth_max"] - args.min_growth,
        "throughput increased after scaling": draining["throughput_per_second"] >= growing["throughput_per_second"] * args.min_speedup,
    }
    result = {"checks": checks, "growing": {k: growing[k] for k in ("depth_start", "depth_end", "throughput_per_second")},
              "draining": {k: draining[k] for k in ("depth_max", "depth_end", "throughput_per_second")},
              "queue_wait_p95_by_priority": growing["queue_wait_p95_by_priority"]}
    write(args.output, result)
    failed = [name for name, ok in checks.items() if not ok]
    if failed:
        raise SystemExit(f"Backlog demo checks failed: {failed}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name, fn in (("snapshot", cmd_snapshot), ("processing", cmd_processing)):
        command = commands.add_parser(name)
        command.add_argument("--output")
        command.set_defaults(run=fn)
    sample = commands.add_parser("sample")
    sample.add_argument("--label", required=True)
    sample.add_argument("--duration", type=float, default=60)
    sample.add_argument("--interval", type=float, default=5)
    sample.add_argument("--output")
    sample.set_defaults(run=cmd_sample)
    wait = commands.add_parser("wait")
    wait.add_argument("condition", choices=["leader-changed", "online", "consumers", "processing", "dlq", "drained", "generated-above"])
    wait.add_argument("value", nargs="?", default="0")
    wait.add_argument("--timeout", type=float, default=120)
    wait.add_argument("--output")
    wait.set_defaults(run=cmd_wait)
    report = commands.add_parser("report")
    report.add_argument("inspection_id")
    report.add_argument("--status", default="GENERATED")
    report.add_argument("--timeout", type=float, default=120)
    report.add_argument("--output")
    report.set_defaults(run=cmd_report)
    verify = commands.add_parser("verify-backlog")
    verify.add_argument("--growing", required=True)
    verify.add_argument("--draining", required=True)
    verify.add_argument("--min-growth", type=int, default=20)
    verify.add_argument("--min-speedup", type=float, default=2.0)
    verify.add_argument("--output")
    verify.set_defaults(run=cmd_verify_backlog)
    parsed = parser.parse_args()
    parsed.run(parsed)
