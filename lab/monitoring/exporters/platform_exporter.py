"""Read-only Kafka assignment + Connect REST status absent from native exporters."""
import asyncio
import logging
import os
import time

import httpx
from aiokafka.admin import AIOKafkaAdminClient
from aiokafka.coordinator.protocol import ConsumerProtocolMemberAssignment
from prometheus_client import Gauge, start_http_server

logging.basicConfig(level=logging.INFO)
logging.getLogger("httpx").setLevel(logging.WARNING)
collected = Gauge('platform_collection_success', 'Last real poll succeeded', ['component'])
last_success = Gauge('platform_collection_timestamp_seconds', 'Last successful poll', ['component'])
connector_running = Gauge('connect_connector_running', 'Connector REST status RUNNING', ['connector'])
task_running = Gauge('connect_task_running', 'Task REST status RUNNING', ['connector', 'task'])
assignments = Gauge('kafka_consumer_partition_assigned', 'Actual group partition assignment', ['consumergroup', 'topic', 'partition', 'client_host'])
members = Gauge('kafka_consumer_members', 'Actual active consumer group members', ['consumergroup'])
CONNECTORS = [f'{s}-postgres-connector' for s in ('vehicle', 'warranty', 'inspection', 'repair')]
GROUPS = ['inspection-service-v2', 'repair-service-v1']


async def poll_connect(client):
    try:
        statuses = []
        for name in CONNECTORS:
            response = await client.get(f'http://debezium-connect:8083/connectors/{name}/status')
            response.raise_for_status()
            statuses.append((name, response.json()))
        task_running.clear()
        for name, status in statuses:
            connector_running.labels(name).set(status['connector']['state'] == 'RUNNING')
            for task in status['tasks']:
                task_running.labels(name, str(task['id'])).set(task['state'] == 'RUNNING')
        collected.labels('connect').set(1)
        last_success.labels('connect').set(time.time())
    except Exception:
        collected.labels('connect').set(0)
        for name in CONNECTORS:
            connector_running.labels(name).set(0)
        task_running.clear()  # Unknown tasks must not retain a stale RUNNING value.
        logging.exception('Connect status collection failed')


async def poll_kafka():
    admin = AIOKafkaAdminClient(bootstrap_servers=os.environ.get('KAFKA_BOOTSTRAP_SERVERS','kafka-1:9092,kafka-2:9092,kafka-3:9092'), request_timeout_ms=5000)
    try:
        async with asyncio.timeout(10):
            await admin.start()
            # aiokafka 0.12 cannot reliably decode multi-group DescribeGroups replies.
            # One request per group uses the same actual Admin API without that path.
            responses = []
            for group in GROUPS:
                responses.extend(await admin.describe_consumer_groups([group]))
        assignments.clear()
        for response in responses:
            for group in response.groups:
                # protocol v1: error_code, group_id, state, protocol_type, protocol, members
                if group[0]:
                    raise RuntimeError(f'Kafka group metadata error {group[0]}')
                members.labels(group[1]).set(len(group[5]))
                for member in group[5]:
                    assignment = ConsumerProtocolMemberAssignment.decode(member[4])
                    for tp in assignment.partitions():
                        assignments.labels(group[1], tp.topic, str(tp.partition), member[2]).set(1)
        collected.labels('kafka').set(1)
        last_success.labels('kafka').set(time.time())
    except Exception:
        members.clear()
        assignments.clear()
        collected.labels('kafka').set(0)
        logging.exception('Kafka assignment collection failed')
    finally:
        await admin.close()


async def main():
    start_http_server(9102)
    async with httpx.AsyncClient(timeout=3) as client:
        while True:
            await asyncio.gather(poll_connect(client), poll_kafka())
            await asyncio.sleep(5)


if __name__ == '__main__':
    asyncio.run(main())
