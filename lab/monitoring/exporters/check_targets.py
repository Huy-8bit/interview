"""Bounded startup readiness: fail when a real required scrape remains down."""
import json
import os
import time
import urllib.parse
import urllib.request

EXPECTED = {'prometheus':1,'fastapi':4,'traffic':1,'kafka':1,'kafka-jmx':3,'debezium':1,'platform':1,'postgres':2,'redis':6,'cadvisor':1,
            'rabbitmq':3,'rabbitmq-queues':3,'report-worker':1}
if os.environ.get('ALLOW_STOPPED_TRAFFIC') == 'true':
    EXPECTED.pop('traffic')
for attempt in range(60):
    try:
        with urllib.request.urlopen('http://prometheus:9090/api/v1/targets',timeout=5) as response:
            targets = json.load(response)['data']['activeTargets']
        bad = []
        for job, minimum in EXPECTED.items():
            entries = [t for t in targets if t['labels'].get('job') == job]
            if len(entries)<minimum or any(t['health']!='up' for t in entries):
                bad.append({'job':job,'expected_min':minimum,'discovered':len(entries),'errors':[t['lastError'] for t in entries if t['health']!='up']})
        if not bad:
            checks = {
                'postgres database connectivity': 'min(pg_up) == 1',
                'redis connectivity': 'sum(redis_up) == 6',
                'rabbitmq cluster': 'count(rabbitmq_identity_info{job="rabbitmq"}) == 3 and max(rabbitmq_unreachable_cluster_peers_count) == 0',
                'report queue metrics': 'count(rabbitmq_detailed_queue_messages{queue=~"inspection.report.(generate|dlq)"}) == 2',
                'connector tasks': 'sum(connect_task_running) == 4',
                'metadata collection': 'sum(platform_collection_success) == 2',
                'container CPU': 'count(count by(service)(container_cpu_usage_seconds_total{service=~"vehicle-service|warranty-service|inspection-service|repair-service|traffic-generator|postgres-primary|postgres-replica|kafka-[123]|redis-[1-6]|debezium-connect"})) >= 17',
                'container RAM': 'count(count by(service)(container_memory_working_set_bytes{service=~"vehicle-service|warranty-service|inspection-service|repair-service|traffic-generator|postgres-primary|postgres-replica|kafka-[123]|redis-[1-6]|debezium-connect"})) >= 17',
            }
            if os.environ.get('ALLOW_STOPPED_TRAFFIC') == 'true':
                checks.pop('container CPU')
                checks.pop('container RAM')
            for label, expression in checks.items():
                url = 'http://prometheus:9090/api/v1/query?' + urllib.parse.urlencode({'query':expression})
                with urllib.request.urlopen(url, timeout=5) as response:
                    if not json.load(response)['data']['result']:
                        bad.append({'metric_check':label})
        if not bad:
            print(f'OK: {len(targets)} Prometheus targets UP',flush=True)
            break
        print('WAIT metrics targets: '+json.dumps(bad),flush=True)
    except Exception as exc:
        print('WAIT Prometheus: '+str(exc),flush=True)
    time.sleep(3)
else:
    raise SystemExit('Prometheus targets did not become ready; inspect http://localhost:9090/targets')
