"""Observe real PostgreSQL replication and Debezium records, never implement CDC.

Run in toolbox. Fault orchestration lives in postgres_cdc_drills.sh.
"""

import argparse
import asyncio
import json
import os
from pathlib import Path

import httpx
from aiokafka import AIOKafkaConsumer, TopicPartition
from aiokafka.admin import AIOKafkaAdminClient
from sqlalchemy import text
from sqlalchemy.engine import URL
from sqlalchemy.ext.asyncio import create_async_engine

from platform_common.db import utcnow
from scripts.cluster_verify import retry, workflow
from scripts.lab_client import LabClient

TABLES = dict(vehicle="vehicles", warranty="warranties", inspection="inspections", repair="repair_requests")
TOPICS = [f"{service}-cdc.public.{table}" for service, table in TABLES.items()]
BOOTSTRAP = os.environ["KAFKA_BOOTSTRAP_SERVERS"]
CONNECT = os.getenv("CONNECT_URL", "http://debezium-connect:8083")


def save(path, data):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(data, indent=2, default=str) + "\n")


def load(path):
    return json.loads(Path(path).read_text())


async def query(sql, *, node="primary", db="postgres", params=None):
    url = URL.create("postgresql+asyncpg", username="platform_admin", password=os.environ["POSTGRES_ADMIN_PASSWORD"], host="postgres-" + node, database=db)
    engine = create_async_engine(url, connect_args={"timeout": 3})
    try:
        async with engine.begin() as conn:
            result = await conn.execute(text(sql), params or {})
            return [dict(row) for row in result.mappings()] if result.returns_rows else []
    finally:
        await engine.dispose()


async def connector_states():
    async with httpx.AsyncClient(timeout=8) as client:
        result = {}
        for service in TABLES:
            r = await client.get(f"{CONNECT}/connectors/{service}-postgres-connector/status")
            r.raise_for_status()
            result[service] = r.json()
        return result


async def topology():
    primary = (await query("SELECT pg_is_in_recovery() AS recovery, pg_current_wal_lsn() AS lsn, current_setting('wal_level') AS wal_level, (SELECT system_identifier::text FROM pg_control_system()) AS system_identifier"))[0]
    replica = (await query("SELECT pg_is_in_recovery() AS recovery, pg_last_wal_receive_lsn() AS receive_lsn, pg_last_wal_replay_lsn() AS replay_lsn, (SELECT system_identifier::text FROM pg_control_system()) AS system_identifier", node="replica"))[0]
    replication = await query("SELECT application_name, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication")
    slots = await query("SELECT slot_name, slot_type, plugin, database, active, restart_lsn, confirmed_flush_lsn, wal_status, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes FROM pg_replication_slots ORDER BY slot_name")
    publications = {s: await query("SELECT p.pubname, t.schemaname, t.tablename FROM pg_publication p JOIN pg_publication_tables t ON p.pubname=t.pubname", db=s + "_db") for s in TABLES}
    admin = AIOKafkaAdminClient(bootstrap_servers=BOOTSTRAP)
    try:
        await admin.start()
        topics = await admin.describe_topics(TOPICS + ["connect-configs", "connect-offsets", "connect-status"])
    finally:
        await admin.close()
    return dict(recorded_at=utcnow(), primary=primary, replica=replica, replication=replication, slots=slots, publications=publications, connectors=await connector_states(), topics=topics)


async def verify():
    async def check():
        data = await topology()
        assert data["primary"]["recovery"] is False and data["primary"]["wal_level"] == "logical"
        assert data["replica"]["recovery"] is True
        assert data["primary"]["system_identifier"] == data["replica"]["system_identifier"]
        assert any(r["application_name"] == "postgres-replica" and r["state"] == "streaming" for r in data["replication"])
        for service, table in TABLES.items():
            slot = next(s for s in data["slots"] if s["slot_name"] == "dbz_" + service)
            assert slot["active"] and slot["plugin"] == "pgoutput" and slot["database"] == service + "_db"
            assert any(t["tablename"] == table for t in data["publications"][service])
            status = data["connectors"][service]
            assert status["connector"]["state"] == "RUNNING" and len(status["tasks"]) == 1
            assert status["tasks"][0]["state"] == "RUNNING"
        for topic in data["topics"]:
            assert topic["error_code"] == 0
            assert len(topic["partitions"]) == (1 if topic["topic"] == "connect-configs" else 3)
            assert all(len(p["replicas"]) == len(p["isr"]) == 3 for p in topic["partitions"])
        return data

    return await retry(check, timeout=150)


async def consumer(topics=TOPICS, offsets=None):
    c = AIOKafkaConsumer(bootstrap_servers=BOOTSTRAP, group_id=None, enable_auto_commit=False, request_timeout_ms=10000)
    await c.start()
    await c.topics()
    partitions = [TopicPartition(t, p) for t in topics for p in sorted(c.partitions_for_topic(t) or [])]
    assert len(partitions) == len(topics) * 3, partitions
    c.assign(partitions)
    ends = await c.end_offsets(partitions)
    for tp in partitions:
        c.seek(tp, offsets[f"{tp.topic}:{tp.partition}"] if offsets is not None else ends[tp])
    return c, {f"{p.topic}:{p.partition}": n for p, n in ends.items()}


def decode(raw):
    if raw is None:
        return None
    value = json.loads(raw)
    return value.get("payload", value)  # Also read schema-enabled historical records.


async def collect(c, expected, *, timeout=120, tombstone=False):
    records, seen, deleted_keys = [], set(), set()
    async with asyncio.timeout(timeout):
        while True:
            batches = await c.getmany(timeout_ms=1000, max_records=500)
            for messages in batches.values():
                for msg in messages:
                    key, value = decode(msg.key), decode(msg.value)
                    entity_id = str(key.get("id")) if key else None
                    if (msg.topic, entity_id) not in expected:
                        continue
                    op = value["op"] if value else "tombstone"
                    seen.add((msg.topic, entity_id, op))
                    if value is None:
                        deleted_keys.add((msg.topic, entity_id))
                    else:
                        assert value["source"]["connector"] == "postgresql"
                        assert value["source"]["lsn"] is not None and value["ts_ms"] is not None
                    records.append(dict(topic=msg.topic, partition=msg.partition, offset=msg.offset, key=key, value=value))
            complete = all(all((topic, entity_id, op) in seen for op in ops) for (topic, entity_id), ops in expected.items())
            if complete and (not tombstone or all(pair in deleted_keys for pair in expected)):
                return records


async def replica_vehicle(client, vehicle_id):
    async def read():
        response = await client.request("vehicle", "GET", f"/vehicles/{vehicle_id}?consistency=eventual")
        assert response.status_code == 200 and response.headers["X-Read-Source"] == "replica", response.text
        return response.json()
    return await retry(read)


async def change_rows(client, *, check_replica=True):
    vehicle = await client.vehicle()
    if check_replica:
        await replica_vehicle(client, vehicle["id"])
    updated = await client.json("vehicle", "PATCH", f"/vehicles/{vehicle['id']}", json={"owner_name": "CDC updated owner"})
    # SQL-only demo: only delete the newly created, uniquely identified lab row.
    deleted = await query("DELETE FROM vehicles WHERE id=:id AND vin=:vin RETURNING id", db="vehicle_db", params={"id": vehicle["id"], "vin": vehicle["vin"]})
    assert len(deleted) == 1
    return dict(vehicle=vehicle, updated=updated, deleted=deleted)


def assert_images(records, changes):
    by_op = {r["value"]["op"]: r["value"] for r in records if r["value"]}
    assert by_op["c"]["before"] is None and by_op["c"]["after"]["owner_name"] == changes["vehicle"]["owner_name"]
    assert by_op["u"]["before"]["owner_name"] == changes["vehicle"]["owner_name"]
    assert by_op["u"]["after"]["owner_name"] == "CDC updated owner"
    assert by_op["d"]["before"]["owner_name"] == "CDC updated owner" and by_op["d"]["after"] is None
    assert "r" not in by_op  # The new changes came from WAL, not another snapshot.


async def main(args):
    client = LabClient()
    c = None
    try:
        if args.mode == "verify":
            result = await verify()
        elif args.mode == "watermark":
            c, offsets = await consumer()
            result = dict(offsets=offsets)
        elif args.mode in ("cdc", "changes", "replica-down"):
            if args.mode != "changes":
                c, _ = await consumer()
            changes = await change_rows(client, check_replica=args.mode != "replica-down")
            result = dict(changes=changes)
            if c:
                result["records"] = await collect(c, {(TOPICS[0], changes["vehicle"]["id"]): {"c", "u", "d"}}, tombstone=True)
                assert_images(result["records"], changes)
            if args.mode == "replica-down":
                vehicle = await client.vehicle()
                r = await client.request("vehicle", "GET", f"/vehicles/{vehicle['id']}?consistency=eventual")
                assert r.status_code == 200 and r.headers["X-Read-Source"] == "primary-fallback", r.text
                result["read_fallback"] = dict(status=r.status_code, source=r.headers["X-Read-Source"], id=r.json()["id"])
                result["replication"] = await query("SELECT application_name,state FROM pg_stat_replication")
                assert not any(row["application_name"] == "postgres-replica" for row in result["replication"])
        elif args.mode == "resume":
            changes = load(args.changes)["changes"]
            c, _ = await consumer(offsets=load(args.state)["offsets"])
            records = await collect(c, {(TOPICS[0], changes["vehicle"]["id"]): {"c", "u", "d"}}, tombstone=True)
            assert_images(records, changes)
            result = dict(records=records, resumed_from_saved_offsets=True, connectors=await connector_states())
        elif args.mode == "primary-prepare":
            vehicle = await client.vehicle()
            await replica_vehicle(client, vehicle["id"])
            result = dict(vehicle=vehicle)
        elif args.mode == "primary-down":
            vehicle = load(args.state)["vehicle"]
            r = await client.request("vehicle", "GET", f"/vehicles/{vehicle['id']}?consistency=eventual")
            assert r.status_code == 200 and r.headers["X-Read-Source"] == "replica", r.text
            write = await client.request("vehicle", "POST", "/vehicles", json={k: vehicle[k] for k in ("vin", "model", "manufacturer", "production_year", "owner_name")})
            assert write.status_code == 503, write.text
            ready = await client.request("vehicle", "GET", "/ready")
            assert ready.status_code == 503
            replica = await query("SELECT pg_is_in_recovery() AS recovery, pg_last_wal_replay_lsn() AS lsn", node="replica")
            assert replica[0]["recovery"] is True
            receiver = await query("SELECT status, sender_host FROM pg_stat_wal_receiver", node="replica")
            assert receiver == []
            result = dict(replica_read_status=r.status_code, write_status=write.status_code, readiness=ready.json(), replica=replica, receiver=receiver, connectors=await connector_states())
        elif args.mode == "lag":
            c, _ = await consumer()
            vehicle = await client.vehicle()
            strong = await client.request("vehicle", "GET", f"/vehicles/{vehicle['id']}")
            stale = await client.request("vehicle", "GET", f"/vehicles/{vehicle['id']}?consistency=eventual")
            assert strong.status_code == 200 and stale.status_code == 404
            assert strong.headers["X-Read-Source"] == "primary"
            lag = await query("SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS bytes FROM pg_stat_replication WHERE application_name='postgres-replica'")
            assert lag[0]["bytes"] > 0
            records = await collect(c, {(TOPICS[0], vehicle["id"]): {"c"}})
            result = dict(vehicle=vehicle, primary_get=strong.status_code, stale_replica_get=stale.status_code, lag=lag, records=records)
        elif args.mode == "caught-up":
            vehicle = load(args.state)["vehicle"]
            result = dict(vehicle=await replica_vehicle(client, vehicle["id"]))
        elif args.mode == "workflow":
            c, _ = await consumer()
            flow = await workflow()
            warranty = (await client.json("warranty", "GET", f"/warranties/vehicle/{flow['vehicle_id']}"))[0]
            ids = [flow["vehicle_id"], warranty["id"], flow["inspection_id"], flow["repair_id"]]
            records = await collect(c, {(topic, entity_id): {"c"} for topic, entity_id in zip(TOPICS, ids, strict=True)})
            result = dict(workflow=flow, records=records)
        elif args.mode == "snapshot":
            c, _ = await consumer(offsets={f"{t}:{p}": 0 for t in TOPICS for p in range(3)})
            result = {}
            async with asyncio.timeout(45):
                while len(result) < len(TOPICS):
                    for messages in (await c.getmany(timeout_ms=1000, max_records=500)).values():
                        for msg in messages:
                            value = decode(msg.value)
                            if value and value["op"] == "r" and msg.topic not in result:
                                result[msg.topic] = dict(key=decode(msg.key), value=value, partition=msg.partition, offset=msg.offset)
        save(args.output, result)
        print("PASS: " + args.mode, flush=True)
    finally:
        if c:
            await c.stop()
        await client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["verify", "watermark", "cdc", "changes", "replica-down", "resume", "primary-prepare", "primary-down", "lag", "caught-up", "workflow", "snapshot"])
    parser.add_argument("--output", default="/tmp/postgres-cdc-result.json")
    parser.add_argument("--state")
    parser.add_argument("--changes")
    asyncio.run(main(parser.parse_args()))
