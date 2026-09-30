"""Verify live samples, provisioned Grafana JSON and every dashboard PromQL."""
import argparse
import asyncio
import json
import math
import os
import re
import time
from pathlib import Path

import httpx

PROM = os.getenv('PROMETHEUS_URL','http://prometheus:9090')
GRAFANA = os.getenv('GRAFANA_URL','http://grafana:3000')
REQUIRED_SERVICES = {'vehicle-service','warranty-service','inspection-service','repair-service','traffic-generator',
                     'postgres-primary','postgres-replica','kafka-1','kafka-2','kafka-3','debezium-connect',*(f'redis-{n}' for n in range(1,7))}


async def query(client, expression):
    response = await client.get(PROM+'/api/v1/query', params={'query':expression})
    response.raise_for_status()
    result = response.json()
    assert result['status']=='success', result
    return result['data']['result']


async def check(output=None):
    evidence = {'recorded_at_unix': time.time(), 'metrics':{}, 'dashboards':[]}
    async with httpx.AsyncClient(timeout=20) as client:
        # DNS discovery and one scrape must catch up after scale-down/recreation.
        deadline=time.monotonic()+60
        while True:
            targets=(await client.get(PROM+'/api/v1/targets')).json()['data']['activeTargets']
            if len(targets)>=21 and all(t['health']=='up' for t in targets):
                break
            if time.monotonic()>=deadline:
                break
            await asyncio.sleep(2)
        assert len(targets)>=21 and all(t['health']=='up' for t in targets), [(t['labels'],t['lastError']) for t in targets if t['health']!='up']
        evidence['targets']=[{'job':t['labels']['job'],'instance':t['labels']['instance'],'health':t['health']} for t in targets]
        required = {
            'api_rps':'sum(rate(http_requests_total[2m]))',
            'generator_requests':'traffic_requests_total',
            'consumer_lag':'kafka_consumergroup_lag{consumergroup="inspection-service-v2"}',
            'pg_connections':'pg_stat_database_numbackends{datname="vehicle_db",role="primary"}',
            'pg_replica':'lab_pg_role_is_replica{role="replica"}',
            'pg_wal':'lab_pg_role_wal_position_bytes',
            'redis_memory':'redis_memory_used_bytes',
            'redis_roles':'redis_instance_info',
            'container_cpu':'container_cpu_usage_seconds_total',
            'container_memory':'container_memory_working_set_bytes',
            'container_limit':'container_spec_memory_limit_bytes',
            'container_network':'container_network_receive_bytes_total',
            'connectors':'connect_connector_running',
            'connect_tasks':'connect_task_running',
            'cdc_events':'debezium_events_seen_total',
            'cdc_delay':'cdc_source_to_consumer_seconds_count',
            'broker_throughput':'kafka_broker_messagesinpersec_total',
            'outbox':'outbox_published_total',
            'assignments':'kafka_consumer_partition_assigned',
            'rabbitmq_nodes':'rabbitmq_identity_info',
            'report_queue_depth':'rabbitmq_detailed_queue_messages{queue="inspection.report.generate"}',
            'report_tasks_submitted':'background_tasks_submitted_total',
            'report_tasks_completed':'background_tasks_completed_total{outcome="generated"}',
            'report_task_duration':'background_task_duration_seconds_count',
        }
        for key,expression in required.items():
            rows=await query(client,expression)
            assert rows and all(math.isfinite(float(r['value'][1])) for r in rows), (key,rows)
            if key in ('api_rps','generator_requests','pg_connections','pg_replica','redis_memory','cdc_events','cdc_delay','broker_throughput','outbox'):
                assert sum(float(r['value'][1]) for r in rows)>0, (key,rows)
            if key.startswith('container_'):
                present={r['metric'].get('service') for r in rows}
                assert REQUIRED_SERVICES <= present, (key,sorted(REQUIRED_SERVICES-present))
            evidence['metrics'][key]={'query':expression,'series':len(rows),'samples':rows}
        for expression,count in [('up{job="rabbitmq"}',3),('pg_up',2),('redis_up',6),('connect_connector_running',4),('connect_task_running',4),('platform_collection_success',2)]:
            rows=await query(client,expression)
            assert len(rows)==count and all(float(r['value'][1])==1 for r in rows), (expression,rows)
        labels=await query(client,'http_requests_total')
        forbidden={'vehicle_id','event_id','request_id','correlation_id','VIN','vin','user_id','inspection_id','task_id'}
        labels+=await query(client,'{__name__=~"background_.*"}')
        for row in labels:
            assert not forbidden.intersection(row['metric'])
            assert not re.search(r'[0-9a-f]{8}-[0-9a-f-]{27}',row['metric'].get('route',''))
        auth=(os.getenv('GRAFANA_USER','admin'),os.getenv('GRAFANA_PASSWORD','lab_grafana_password'))
        datasource=await client.get(GRAFANA+'/api/datasources/uid/lab-prometheus',auth=auth)
        datasource.raise_for_status()
        assert datasource.json()['url']=='http://prometheus:9090'
        evidence['datasource']={'uid':datasource.json()['uid'],'url':datasource.json()['url']}
        for path in sorted(Path('monitoring/grafana/dashboards').glob('*.json')):
            expected=json.loads(path.read_text())
            response=await client.get(GRAFANA+'/api/dashboards/uid/'+expected['uid'],auth=auth)
            response.raise_for_status()
            live=response.json()['dashboard']
            assert live['title']==expected['title']
            info={'uid':live['uid'],'title':live['title'],'panels':[]}
            for panel in live['panels']:
                for target in panel.get('targets',[]):
                    expression=target['expr']
                    for name in ('consumer_group','redis_node','database','instance','service','topic'):
                        expression=expression.replace('$'+name,'.*')
                    rows=await query(client,expression)
                    info['panels'].append({'title':panel['title'],'query':expression,'series':len(rows)})
            evidence['dashboards'].append(info)
        assert len(evidence['dashboards'])>=10
    if output:
        Path(output).parent.mkdir(parents=True,exist_ok=True)
        Path(output).write_text(json.dumps(evidence,indent=2)+'\n')
    panels=[p for d in evidence['dashboards'] for p in d['panels']]
    print(json.dumps({'targets_up':len(targets),'dashboards':len(evidence['dashboards']),'queries_valid':len(panels),
                      'empty_panels':[p['title'] for p in panels if not p['series']], 'output':output},indent=2))
    return evidence


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output')
    args=parser.parse_args()
    asyncio.run(check(args.output))
