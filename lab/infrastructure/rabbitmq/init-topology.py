"""Idempotent RabbitMQ topology for inspection report tasks, via the management HTTP API.

Declares only what the report workload needs and verifies that the work queue is a
replicated quorum queue on a formed three-node cluster. Queue arguments must stay
identical to the Celery Queue declaration in app/reports/celery_app.py, because a
redeclaration with different x-arguments is rejected by the broker.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from base64 import b64encode

NODES = [n.strip() for n in os.getenv("RABBITMQ_MANAGEMENT_NODES", "rabbitmq-1,rabbitmq-2,rabbitmq-3").split(",")]
EXPECTED_NODES = int(os.getenv("RABBITMQ_EXPECTED_NODES", "3"))
AUTH = "Basic " + b64encode(f"{os.environ['RABBITMQ_USER']}:{os.environ['RABBITMQ_PASSWORD']}".encode()).decode()
VHOST = urllib.parse.quote("/", safe="")

EXCHANGE, DLX = "inspection.reports", "inspection.reports.dlx"
WORK_QUEUE, DLQ = "inspection.report.generate", "inspection.report.dlq"
ROUTING_KEY = "report.generate"
QUORUM = {"x-queue-type": "quorum"}
# Policies hold tunables (dead-lettering, delivery limit) so they can change without
# redeclaring queues. at-least-once dead-lettering keeps a message in the source queue
# until the DLQ confirms it; quorum queues require reject-publish overflow for that.
POLICIES = {
    "inspection-report-work": {
        "pattern": r"^inspection\.report\.generate$",
        "apply-to": "quorum_queues",
        "priority": 10,
        "definition": {
            "dead-letter-exchange": DLX,
            "dead-letter-routing-key": "report.dead",
            "dead-letter-strategy": "at-least-once",
            "overflow": "reject-publish",
            "delivery-limit": int(os.getenv("REPORT_DELIVERY_LIMIT", "5")),
        },
    },
    # The DLQ is a parking lot: inspecting it (get + requeue) must never drop a
    # message, so disable the quorum queue default delivery limit (20 in 4.x).
    "inspection-report-dlq": {
        "pattern": r"^inspection\.report\.dlq$",
        "apply-to": "quorum_queues",
        "priority": 10,
        "definition": {"delivery-limit": -1},
    },
}


def call(method, path, body=None):
    last = None
    for node in NODES:
        request = urllib.request.Request(
            f"http://{node}:15672/api{path}",
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": AUTH, "Content-Type": "application/json"},
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                payload = response.read()
                return json.loads(payload) if payload else None
        except urllib.error.HTTPError as exc:
            if exc.code < 500:
                raise SystemExit(f"{method} {path} -> {exc.code}: {exc.read().decode()[:500]}") from None
            last = exc
        except OSError as exc:
            last = exc
    raise ConnectionError(f"No management API reachable for {method} {path}: {last}")


def wait_for_cluster(deadline):
    while True:
        try:
            nodes = call("GET", "/nodes")
            running = sorted(n["name"] for n in nodes if n.get("running"))
            if len(running) >= EXPECTED_NODES:
                print(f"Cluster formed: {', '.join(running)}", flush=True)
                return
            print(f"WAIT cluster: running={running}", flush=True)
        except ConnectionError as exc:
            print(f"WAIT management API: {exc}", flush=True)
        if time.monotonic() > deadline:
            raise SystemExit(f"Cluster did not reach {EXPECTED_NODES} running nodes")
        time.sleep(2)


def main():
    wait_for_cluster(time.monotonic() + float(os.getenv("RABBITMQ_INIT_TIMEOUT", "180")))
    for exchange in (EXCHANGE, DLX):
        # Topic, not direct: Celery native delayed delivery (retry countdowns on quorum
        # queues) re-routes messages with a prefixed routing key.
        call("PUT", f"/exchanges/{VHOST}/{exchange}", {"type": "topic", "durable": True, "auto_delete": False, "internal": False, "arguments": {}})
    for queue in (WORK_QUEUE, DLQ):
        call("PUT", f"/queues/{VHOST}/{queue}", {"durable": True, "auto_delete": False, "arguments": QUORUM})
    call("POST", f"/bindings/{VHOST}/e/{EXCHANGE}/q/{WORK_QUEUE}", {"routing_key": ROUTING_KEY, "arguments": {}})
    call("POST", f"/bindings/{VHOST}/e/{DLX}/q/{DLQ}", {"routing_key": "#", "arguments": {}})
    for name, policy in POLICIES.items():
        call("PUT", f"/policies/{VHOST}/{name}", policy)

    deadline = time.monotonic() + 60
    while True:
        queues = {q: call("GET", f"/queues/{VHOST}/{q}") for q in (WORK_QUEUE, DLQ)}
        work = queues[WORK_QUEUE]
        ready = (
            all(q.get("type") == "quorum" and len(q.get("members", [])) >= EXPECTED_NODES and q.get("leader") for q in queues.values())
            and work.get("policy") == "inspection-report-work"
            and queues[DLQ].get("policy") == "inspection-report-dlq"
        )
        if ready:
            break
        if time.monotonic() > deadline:
            raise SystemExit(f"Queues not replicated or policy not applied: {json.dumps(queues)[:2000]}")
        time.sleep(1)
    for name, queue in queues.items():
        print(json.dumps({
            "queue": name, "type": queue["type"], "leader": queue["leader"], "members": sorted(queue["members"]),
            "policy": queue.get("policy"), "effective_policy": queue.get("effective_policy_definition"),
            "messages": queue.get("messages", 0),
        }), flush=True)
    print("RabbitMQ topology ready", flush=True)


if __name__ == "__main__":
    try:
        main()
    except ConnectionError as exc:
        sys.exit(str(exc))
