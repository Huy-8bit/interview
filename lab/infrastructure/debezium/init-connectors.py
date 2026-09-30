"""Idempotent connector registration; no application-layer CDC implementation."""

import json
import os
import time
import urllib.error
import urllib.request

BASE = os.getenv("CONNECT_URL", "http://debezium-connect:8083")
TABLES = dict(vehicle="vehicles", warranty="warranties", inspection="inspections", repair="repair_requests")


def request(path, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json"},
        method="PUT" if body is not None else "GET",
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)


def config(service, table):
    return {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "tasks.max": "1",
        "database.hostname": "postgres-primary",
        "database.port": "5432",
        "database.user": "debezium",
        "database.password": os.environ["DEBEZIUM_PASSWORD"],
        "database.dbname": service + "_db",
        "topic.prefix": service + "-cdc",
        "plugin.name": "pgoutput",
        "slot.name": "dbz_" + service,
        "slot.drop.on.stop": "false",
        "publication.name": "dbz_" + service,
        "publication.autocreate.mode": "disabled",
        "table.include.list": "public." + table,
        "snapshot.mode": "initial",
        "tombstones.on.delete": "true",
        "heartbeat.interval.ms": "5000",
        "heartbeat.action.query": "INSERT INTO public.cdc_heartbeat VALUES (1, now()) ON CONFLICT (id) DO UPDATE SET updated_at=EXCLUDED.updated_at",
        "errors.max.retries": "-1",
        "retriable.restart.connector.wait.ms": "5000",
    }


def main():
    for service, table in TABLES.items():
        name = service + "-postgres-connector"
        desired = config(service, table)
        deadline = time.monotonic() + 180
        while True:
            try:
                try:
                    current = request("/connectors/" + name + "/config")
                except urllib.error.HTTPError as exc:
                    if exc.code != 404:
                        raise
                    current = {}
                if any(current.get(k) != v for k, v in desired.items()):
                    request("/connectors/" + name + "/config", desired)
                status = request("/connectors/" + name + "/status")
                tasks = status.get("tasks", [])
                if status["connector"]["state"] == "RUNNING" and tasks and all(t["state"] == "RUNNING" for t in tasks):
                    print(name + ": connector and task RUNNING", flush=True)
                    break
                last = {"connector": status["connector"]["state"], "tasks": [t["state"] for t in tasks]}
            except (urllib.error.URLError, TimeoutError, KeyError) as exc:
                last = type(exc).__name__
            if time.monotonic() >= deadline:
                raise RuntimeError(f"{name} did not become ready: {last}")
            time.sleep(1)


if __name__ == "__main__":
    main()
