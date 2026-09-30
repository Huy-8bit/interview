"""Build provisioned dashboards from this repo's real exporter/application contracts."""
import json
from pathlib import Path

ROOT = Path(__file__).parent / 'grafana/dashboards'
DATASOURCE = {'type': 'prometheus', 'uid': 'lab-prometheus'}


def variable(name, metric, label):
    return dict(name=name, label=name.replace('_',' ').title(), type='query', datasource=DATASOURCE,
                query=f'label_values({metric}, {label})', refresh=2, multi=True, includeAll=True,
                allValue='.*', current={'text':'All','value':'$__all'})


def dashboard(uid, title, panels, variables=()):
    result = dict(uid=uid, title=title, tags=['vehicle-lab'], schemaVersion=40, version=1, timezone='browser',
                  refresh='10s', time={'from':'now-15m','to':'now'}, editable=False,
                  templating={'list':list(variables)}, panels=[])
    for index, item in enumerate(panels):
        label, expression, unit = item[:3]
        description = item[3] if len(item)>3 else 'Source: live Prometheus samples. Rate window 2m; scrape interval 10s.'
        thresholds = [{'color':'green','value':None},{'color':'yellow','value':100},{'color':'red','value':1000}] if 'Lag' in label and unit=='short' else [{'color':'green','value':None}]
        result['panels'].append(dict(id=index+1, title=label, type='timeseries', datasource=DATASOURCE,
            description=description, gridPos={'x':(index%2)*12,'y':(index//2)*8,'w':12,'h':8},
            targets=[{'refId':'A','expr':expression}],
            fieldConfig={'defaults':{'unit':unit,'thresholds':{'mode':'absolute','steps':thresholds},
                'custom':{'drawStyle':'line','lineWidth':2,'fillOpacity':10,'showPoints':'never','thresholdsStyle':{'mode':'line'}}},'overrides':[]},
            options={'tooltip':{'mode':'multi'},'legend':{'displayMode':'table','placement':'bottom','calcs':['lastNotNull','max']}}))
    (ROOT / f'{uid}.json').write_text(json.dumps(result, indent=2)+'\n')


svc=variable('service','http_requests_total','service')
inst=variable('instance','http_requests_total','instance')
topic=variable('topic','kafka_topic_partitions','topic')
group=variable('consumer_group','kafka_consumergroup_lag','consumergroup')
selector='service=~"$service",instance=~"$instance"'
http='{'+selector+'}'
lag='kafka_consumergroup_lag{consumergroup=~"$consumer_group",topic=~"$topic"}'

def latency(q, select=''):
    return f'histogram_quantile({q}, sum by (le,service) (rate(http_request_duration_seconds_bucket{select}[2m])))'


dashboard('lab-overview','System Overview',[
 ('Total RPS','sum(rate(http_requests_total[2m]))','reqps'),
 ('P95 API Latency',latency(.95),'s'),
 ('HTTP Success Rate','100 * sum(rate(http_requests_total{status_code=~"2.."}[2m])) / clamp_min(sum(rate(http_requests_total[2m])),0.001)','percent'),
 ('HTTP Error Rate — 5xx','100 * (sum(rate(http_requests_total{status_code=~"5.."}[2m])) or vector(0)) / clamp_min(sum(rate(http_requests_total[2m])),0.001)','percent'),
 ('Service Availability','up{job="fastapi"}','short'),
 ('Total Consumer Lag','sum(kafka_consumergroup_lag)','short'),
 ('PostgreSQL Connections','sum by(role) (pg_stat_database_numbackends)','short'),
 ('Redis Memory','sum(redis_memory_used_bytes)','bytes'),
 ('Container CPU','sum by(service) (rate(container_cpu_usage_seconds_total[2m]))','cores'),
 ('Container RAM','sum by(service) (container_memory_working_set_bytes)','bytes'),
 ('DB Pool Saturation','100 * sum by(service) (db_pool_checked_out{role="primary"}) / sum by(service)(db_pool_capacity{role="primary"})','percent'),
 ('Outbox Backlog','max by(service)(outbox_pending_events)','short')])

api=[('Requests/sec by Service',f'sum by(service)(rate(http_requests_total{http}[2m]))','reqps'),
     ('RPS by Endpoint / Method',f'sum by(service,route,method)(rate(http_requests_total{http}[2m]))','reqps'),
     ('Average Latency',f'sum by(service)(rate(http_request_duration_seconds_sum{http}[2m])) / clamp_min(sum by(service)(rate(http_request_duration_seconds_count{http}[2m])),0.001)','s')]
api += [(f'P{int(q*100)} Latency',latency(q,http),'s') for q in (.5,.95,.99)]
api += [('Errors by Service',f'sum by(service,status_code)(rate(http_request_errors_total{http}[2m]))','reqps'),
        ('Errors by Endpoint',f'sum by(service,route,status_code)(rate(http_request_errors_total{http}[2m]))','reqps'),
        ('Responses 2xx / 4xx / 5xx',f'sum by(service,status_class)(label_replace(rate(http_requests_total{http}[2m]),"status_class","$1xx","status_code","([245]).."))','reqps'),
        ('Active Requests',f'sum by(service)(http_requests_in_progress{http})','short'),
        ('DB Pool Checked Out',f'db_pool_checked_out{http}','short'),
        ('DB Pool Idle Connections',f'db_pool_idle_connections{http}','short'),
        ('DB Pool Timeouts',f'sum by(service)(rate(db_pool_timeouts_total{http}[2m]))','ops')]
api += [(f'{name.title()} Service RPS',f'sum(rate(http_requests_total{{service="{name}-service"}}[2m]))','reqps') for name in ('vehicle','warranty','inspection','repair')]
dashboard('lab-fastapi','FastAPI Services',api,[svc,inst])

dashboard('lab-kafka','Kafka Cluster',[
 ('Broker Availability','up{job="kafka-jmx"}','short'),('Broker Count','kafka_brokers','short'),
 ('Topic Count','count(kafka_topic_partitions)','short'),('Partition Count','sum(kafka_topic_partitions{topic=~"$topic"})','short'),
 ('Partition Leaders','kafka_topic_partition_leader{topic=~"$topic"}','short'),
 ('In-Sync Replicas','kafka_topic_partition_in_sync_replica{topic=~"$topic"}','short'),
 ('Under Replicated Partitions','sum(kafka_replica_underreplicatedpartitions)','short'),
 ('Offline Partitions','max(kafka_controller_offlinepartitionscount)','short'),
 ('Messages In/sec','sum by(instance)(rate(kafka_broker_messagesinpersec_total[2m]))','ops'),
 ('Bytes In/sec','sum by(instance)(rate(kafka_broker_bytesinpersec_total[2m]))','Bps'),
 ('Bytes Out/sec','sum by(instance)(rate(kafka_broker_bytesoutpersec_total[2m]))','Bps'),
 ('Broker Request Mean Latency','kafka_request_latency_seconds','s','Mean from Kafka JMX TotalTimeMs. This is not P95.')],[topic])

dashboard('lab-consumers','Kafka Consumer Groups — Consumer Lag',[
 ('Total Consumer Lag',f'sum({lag})','short'),('Consumer Lag by Group',f'sum by(consumergroup)({lag})','short'),
 ('Consumer Lag by Topic',f'sum by(consumergroup,topic)({lag})','short'),('Top Lagging Partitions',f'topk(10,{lag})','short'),
 ('Current Committed Offset','kafka_consumergroup_current_offset{consumergroup=~"$consumer_group",topic=~"$topic"}','short'),
 ('Log End Offset','kafka_topic_partition_current_offset{topic=~"$topic"}','short'),
 ('Consumer Members','kafka_consumer_members{consumergroup=~"$consumer_group"}','short'),
 ('Partition Assignment','kafka_consumer_partition_assigned{consumergroup=~"$consumer_group",topic=~"$topic"}','short','Each series identifies group/topic/partition/client_host from Kafka Admin API; zero or overlapping assignments during rebalance are transient.'),
 ('Processed Events/sec','sum by(service,topic)(rate(events_processed_total{topic=~"$topic"}[2m]))','ops'),
 ('Event Processing P95','histogram_quantile(0.95,sum by(le,service)(rate(event_processing_duration_seconds_bucket{topic=~"$topic"}[2m])))','s'),
 ('Retry / Duplicate / DLQ','sum by(__name__,service)({__name__=~"events_(retried|duplicate|dlq)_total"})','short'),
 ('Metadata Collection Success','platform_collection_success{component="kafka"}','short')],[group,topic])

db='{datname=~"$database"}'
pg=[('Primary / Replica Exporter DB Status','pg_up','short'),('Physical Replica Role','lab_pg_role_is_replica','short'),
 ('Connections by DB',f'pg_stat_database_numbackends{db}','short'),('Active / Idle Connections',f'lab_pg_activity_connections{db}','short'),
 ('Transactions/sec',f'sum by(datname,role)(rate(pg_stat_database_xact_commit{db}[2m]) + rate(pg_stat_database_xact_rollback{db}[2m]))','ops'),
 ('Commits/sec',f'rate(pg_stat_database_xact_commit{db}[2m])','ops'),('Rollbacks/sec',f'rate(pg_stat_database_xact_rollback{db}[2m])','ops'),
 ('Deadlocks',f'pg_stat_database_deadlocks{db}','short'),('Locks',f'pg_locks_count{db}','short'),
 ('Database Size',f'pg_database_size_bytes{db}','bytes'),
 ('Buffer Cache Hit Ratio',f'100 * rate(pg_stat_database_blks_hit{db}[2m]) / clamp_min(rate(pg_stat_database_blks_hit{db}[2m]) + rate(pg_stat_database_blks_read{db}[2m]),0.001)','percent'),
 ('Replication Lag Bytes','lab_pg_replication_lag_bytes','bytes'),('Replication Replay Ack Delay','lab_pg_replication_replay_lag_seconds','s','May disappear on idle primary. Use byte lag for current backlog.'),
 ('WAL Position — Primary / Replica','lab_pg_role_wal_position_bytes','bytes'),
 ('Age of Last Replayed Transaction','lab_pg_role_last_replay_age_seconds{role="replica"}','s','This age grows when primary is idle. It is NOT current replication lag.'),
 ('Retained WAL by Slot','lab_pg_slot_retained_bytes','bytes'),('Replication Slot Active','lab_pg_slot_active','short'),
 ('Longest Transactions',f'lab_pg_activity_longest_transaction_seconds{db}','s')]
pg += [(f'Rows {title}/sec',f'rate(pg_stat_database_tup_{metric}{db}[2m])','ops') for title,metric in [('Inserted','inserted'),('Updated','updated'),('Deleted','deleted')]]
dashboard('lab-postgres','PostgreSQL',pg,[variable('database','pg_stat_database_numbackends','datname')])

redis='{instance=~"$redis_node"}'
dashboard('lab-redis','Redis Cluster',[
 ('Redis Node Up',f'redis_up{redis}','short'),('Master / Replica Role',f'redis_instance_info{redis}','short'),
 ('Memory Used',f'redis_memory_used_bytes{redis}','bytes'),('Memory Limit',f'redis_memory_max_bytes{redis}','bytes'),
 ('Connected Clients',f'redis_connected_clients{redis}','short'),('Commands/sec',f'rate(redis_commands_processed_total{redis}[2m])','ops'),
 ('Cache Hit Rate',f'rate(redis_keyspace_hits_total{redis}[2m])','ops'),('Cache Miss Rate',f'rate(redis_keyspace_misses_total{redis}[2m])','ops'),
 ('Cache Hit Ratio',f'100 * rate(redis_keyspace_hits_total{redis}[2m]) / clamp_min(rate(redis_keyspace_hits_total{redis}[2m]) + rate(redis_keyspace_misses_total{redis}[2m]),0.001)','percent'),
 ('Application Vehicle Cache Hits/Misses','sum by(__name__)({__name__=~"vehicle_cache_(hit|miss)_total",job="fastapi"})','short'),
 ('Key Count',f'redis_db_keys{redis}','short'),('Expired Keys/sec',f'rate(redis_expired_keys_total{redis}[2m])','ops'),
 ('Evicted Keys/sec',f'rate(redis_evicted_keys_total{redis}[2m])','ops'),('Replica Master Link',f'redis_master_link_up{redis}','short')],[variable('redis_node','redis_up','instance')])

dashboard('lab-cdc','CDC / Debezium',[
 ('Connector RUNNING','connect_connector_running','short'),('Task RUNNING','connect_task_running','short'),
 ('Captured Events/sec','rate(debezium_events_seen_total{context="streaming"}[2m])','ops'),
 ('Source Record Poll Rate','rate(kafka_connect_source_record_poll_total[2m])','ops'),
 ('Source Record Write Rate','rate(kafka_connect_source_record_write_total[2m])','ops'),
 ('CDC Processing Lag — Connector','debezium_millisecondsbehindsource / 1000','s'),
 ('CDC Processing Lag — Source to C P95','histogram_quantile(0.95,sum by(le,connector)(rate(cdc_source_to_consumer_seconds_bucket[2m])))','s','Source transaction timestamp to Inspection handler, including Kafka lag and intentional processing delay.'),
 ('Queue Utilization','100 * (1 - debezium_queueremainingcapacity / clamp_min(debezium_queuetotalcapacity,1))','percent'),
 ('Snapshot Running','debezium_snapshotrunning','short'),('Snapshot Completed','debezium_snapshotcompleted','short'),
 ('Connector Record Errors','kafka_connect_record_errors_total','short'),('Retained WAL — Logical Slots','lab_pg_slot_retained_bytes{slot_type="logical"}','bytes'),
 ('CDC Operations at Inspection','sum by(operation)(rate(warranty_cdc_events_total[2m]))','ops')])

resource='{service=~"$service"}'
dashboard('lab-containers','Container Resources',[
 ('CPU by Container',f'rate(container_cpu_usage_seconds_total{resource}[2m])','cores'),
 ('RAM Working Set',f'container_memory_working_set_bytes{resource}','bytes'),
 ('RAM Usage',f'container_memory_usage_bytes{resource}','bytes'),('Memory Limit',f'container_spec_memory_limit_bytes{resource}','bytes','Without a Docker memory limit cAdvisor reports the Linux VM capacity, not a service reservation.'),
 ('Network Receive',f'rate(container_network_receive_bytes_total{resource}[2m])','Bps'),
 ('Network Transmit',f'rate(container_network_transmit_bytes_total{resource}[2m])','Bps'),
 ('Container Start Time',f'container_start_time_seconds{resource}','dateTimeAsIso','Use a new start timestamp to detect recreation; cAdvisor does not export a reliable Docker restart-count metric.')],[variable('service','container_memory_working_set_bytes','service')])

business=[(name,f'sum by(service)(rate({metric}{{job="fastapi"}}[2m]))','ops') for name,metric in [
 ('Vehicles Created/sec','vehicles_created_total'),('Warranties Created/sec','warranties_created_total'),('Inspections Created/sec','inspections_created_total'),
 ('Inspection PASS/sec','inspections_passed_total'),('Inspection FAIL/sec','inspections_failed_total'),('Repairs Created/sec','repairs_created_total'),
 ('Warranty Coverage Checks/sec','warranty_coverage_check_total')]]
business += [('CDC Events/sec','sum by(operation)(rate(warranty_cdc_events_total[2m]))','ops'),
 ('Kafka Domain Events/sec','sum by(service,event_type)(rate(events_processed_total{event_type!="warranty.cdc"}[2m]))','ops'),
 ('Outbox Backlog','max by(service)(outbox_pending_events)','short'),('Outbox Publishes/sec','sum by(service)(rate(outbox_published_total[2m]))','ops'),
 ('Outbox Publish Failures/sec','sum by(service)(rate(outbox_publish_failed_total[2m]))','ops'),
 ('Vehicle → Warranty Pending REST','max(warranty_provision_pending_requests{service="vehicle-service"})','short'),
 ('A → B / D → B REST P95','histogram_quantile(0.95,sum by(le,service,target_service,endpoint)(rate(service_client_request_duration_seconds_bucket[2m])))','s'),
 ('Service REST Errors','sum by(service,target_service,status_code)(rate(service_client_errors_total[2m])) or on(service,target_service) (0 * sum by(service,target_service)(rate(service_client_requests_total[2m])))','ops','Zero fallback only for service pairs with observed requests and no error series; missing scrapes still produce no data.'),
 ('DB Metrics Collection Health','metrics_db_collection_success','short')]
dashboard('lab-business','Business Flow',business)

dashboard('lab-traffic','Synthetic Traffic / Load Generator',[
 ('Traffic Requests/sec','rate(traffic_requests_total[2m])','reqps'),('Traffic Failed Requests/sec','rate(traffic_requests_failed_total[2m])','reqps'),
 ('Completed Flows/sec','rate(traffic_flow_completed_total[2m])','ops'),('Failed Flows/sec','rate(traffic_flow_failed_total[2m])','ops'),
 ('Traffic P95 Latency','histogram_quantile(0.95,sum by(le)(rate(traffic_request_duration_seconds_bucket[2m])))','s'),
 ('Traffic Retries/sec','rate(traffic_retries_total[2m])','ops'),
 ('Observed Vehicles / Inspections / Repairs','{__name__=~"(vehicles|inspections|repairs)_created_total",job="traffic"}','short','Generator observations are separate from committed service counters. Never sum these with job=fastapi.'),
 ('Controlled Load Creates/sec','rate(traffic_load_creates_total[2m])','ops'),
 ('Generator CPU','rate(container_cpu_usage_seconds_total{service="traffic-generator"}[2m])','cores'),
 ('Generator RAM','container_memory_working_set_bytes{service="traffic-generator"}','bytes')])
print(f'Generated {len(list(ROOT.glob("*.json")))} dashboards')
