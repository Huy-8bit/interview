"""Independent test observer. Only this toolbox probe reads Kafka, never the simulator."""
import argparse
import asyncio
import json
import os
from pathlib import Path

from aiokafka import AIOKafkaConsumer, TopicPartition

from scripts.postgres_cdc_verify import decode, save

TOPICS = [f"{s}-events" for s in ("vehicle", "warranty", "inspection", "repair")] + ["vehicle-cdc.public.vehicles", "warranty-cdc.public.warranties", "inspection-cdc.public.inspections", "repair-cdc.public.repair_requests"]


async def main(args):
    consumer = AIOKafkaConsumer(bootstrap_servers=os.environ["KAFKA_BOOTSTRAP_SERVERS"], group_id=None, enable_auto_commit=False)
    await consumer.start()
    try:
        await consumer.topics()
        partitions = [TopicPartition(t, p) for t in TOPICS for p in sorted(consumer.partitions_for_topic(t))]
        consumer.assign(partitions)
        ends = await consumer.end_offsets(partitions)
        if args.mode == "watermark":
            save(args.output, {f"{p.topic}:{p.partition}": n for p, n in ends.items()})
            return
        offsets = json.loads(Path(args.state).read_text())
        for p in partitions:
            consumer.seek(p, offsets[f"{p.topic}:{p.partition}"])
        logs = [json.loads(line) for line in Path(args.log).read_text().splitlines() if line.startswith("{")]
        completed = [r for r in logs if r["action"] == "flow_completed"]
        assert len(completed) == 1, logs[-3:]
        flow = completed[0]
        requests = [r for r in logs if "method" in r]
        assert all(r["correlation_id"] == flow["correlation_id"] for r in requests)
        assert len({r["request_id"] for r in requests}) == len(requests)
        assert all(r["response_request_id"] == r["request_id"] for r in requests if r["status_code"] is not None)
        cache = [r for r in logs if r["action"] == "cache_observation"]
        assert [(r["expected"], r["observed"]) for r in cache] == [("MISS", "MISS"), ("HIT", "HIT"), ("MISS", "MISS")]
        if flow["duplicated"]:
            assert any(r["action"] == "idempotency_verified" and r["unique_inspections"] == 1 for r in logs)
        inspection_event = "inspection.failed" if flow["inspection_result"] == "FAIL" else "inspection.passed"
        expected_domain = {"vehicle.created", "vehicle.updated", "warranty.created", inspection_event}
        if flow["inspection_result"] == "FAIL":
            expected_domain.add("repair.created")
        expected_cdc = {("vehicle-cdc.public.vehicles", "c"), ("vehicle-cdc.public.vehicles", "u"), ("warranty-cdc.public.warranties", "c"), ("inspection-cdc.public.inspections", "c"), ("inspection-cdc.public.inspections", "u")}
        if flow["inspection_result"] == "FAIL":
            expected_cdc.add(("repair-cdc.public.repair_requests", "c"))
        if flow["deleted"]:
            expected_cdc |= {("vehicle-cdc.public.vehicles", "d"), ("vehicle-cdc.public.vehicles", "tombstone")}
        domain, cdc, seen_domain, seen_cdc = [], [], set(), set()
        async with asyncio.timeout(120):
            while not (expected_domain <= seen_domain and expected_cdc <= seen_cdc):
                for messages in (await consumer.getmany(timeout_ms=1000, max_records=1000)).values():
                    for msg in messages:
                        value = decode(msg.value)
                        key = msg.key.decode() if msg.topic.endswith("-events") and msg.key else decode(msg.key)
                        record = dict(topic=msg.topic, partition=msg.partition, offset=msg.offset, key=key, value=value)
                        if msg.topic.endswith("-events"):
                            if value and value.get("correlation_id") == flow["correlation_id"]:
                                domain.append(record)
                                seen_domain.add(value["event_type"])
                                print(f"Observed domain {value['event_type']}", flush=True)
                        elif value:
                            row = value.get("after") or value.get("before") or {}
                            if row.get("id") == flow["vehicle_id"] or row.get("vehicle_id") == flow["vehicle_id"]:
                                assert value["source"]["connector"] == "postgresql" and value["source"]["lsn"] is not None
                                if msg.topic.startswith("vehicle-cdc"):
                                    assert row["simulation_run_id"] == flow["run_id"]
                                cdc.append(record)
                                seen_cdc.add((msg.topic, value["op"]))
                                print(f"Observed CDC {msg.topic} {value['op']}", flush=True)
                        elif msg.topic.startswith("vehicle-cdc") and key and key.get("id") == flow["vehicle_id"]:
                            cdc.append(record)
                            seen_cdc.add((msg.topic, "tombstone"))
                            print("Observed CDC vehicle tombstone", flush=True)
        save(args.output, dict(flow=flow, summary=logs[-1], request_count=len(requests), cache=cache, domain_records=domain, cdc_records=cdc, correlation_propagated=True))
        print("PASS: REST traffic, duplicate/cache observations, correlated domain events and WAL CDC")
    finally:
        await consumer.stop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["watermark", "verify"])
    parser.add_argument("--state")
    parser.add_argument("--log")
    parser.add_argument("--output", required=True)
    asyncio.run(main(parser.parse_args()))
