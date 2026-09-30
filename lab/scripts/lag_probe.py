"""Sample Prometheus around a bounded, real Kafka consumer scale experiment."""
import argparse
import asyncio
import json
import statistics
import time
from pathlib import Path

import httpx
from monitoring_verify import query

GROUP = 'inspection-service-v2'


async def value(client, expression):
    rows=await query(client,expression)
    return sum(float(row['value'][1]) for row in rows)


async def sample(args):
    samples=[]
    async with httpx.AsyncClient(timeout=10) as client:
        deadline=time.monotonic()+90
        while time.monotonic()<deadline:
            count=await value(client,f'kafka_consumer_members{{consumergroup="{GROUP}"}}')
            assignments=await query(client,f'kafka_consumer_partition_assigned{{consumergroup="{GROUP}"}}')
            keys=[(r['metric']['topic'],r['metric']['partition']) for r in assignments]
            if count==args.members and len(keys)==len(set(keys))==6:
                break
            await asyncio.sleep(3)
        else:
            raise AssertionError(f'Expected {args.members} stable members and 6 unique assignments')
        started=time.monotonic()
        while time.monotonic()-started<=args.duration:
            metrics={
                'lag':f'sum(kafka_consumergroup_lag{{consumergroup="{GROUP}"}})',
                'processed_per_second':'sum(rate(events_processed_total{service="inspection-service"}[30s]))',
                'load_created':'traffic_load_creates_total',
                'members':f'kafka_consumer_members{{consumergroup="{GROUP}"}}',
                'api_rps':'sum(rate(http_requests_total{service="vehicle-service"}[30s]))',
            }
            row={'time':time.time(),'elapsed':round(time.monotonic()-started,1)}
            for key,expression in metrics.items():
                row[key]=await value(client,expression)
            samples.append(row)
            print(json.dumps(row),flush=True)
            await asyncio.sleep(5)
        result={'members':args.members,'samples':samples,'assignments':assignments}
        Path(args.output).write_text(json.dumps(result,indent=2)+'\n')


def verify(args):
    one=json.loads(Path(args.single).read_text())
    three=json.loads(Path(args.scaled).read_text())
    a,b=one['samples'],three['samples']
    assert max(s['lag'] for s in a)-a[0]['lag']>=30, ('lag did not rise',a)
    assert all(s['members']==3 for s in b), ('unstable group after readiness',b)
    peak=max(s['lag'] for s in b[:6])
    final=statistics.mean(s['lag'] for s in b[-3:])
    assert final < peak * .5, ('lag did not fall enough',peak,final)
    single_rate=statistics.mean(s['processed_per_second'] for s in a[6:])
    scaled_rate=max(statistics.mean(s['processed_per_second'] for s in b[i:i+6]) for i in range(6,len(b)-5))
    assert scaled_rate>single_rate*1.25, (single_rate,scaled_rate)
    assert b[-1]['load_created']>b[0]['load_created']+50, 'Workload stopped before catch-up measurement'
    result=dict(single_peak_lag=max(s['lag'] for s in a), scaled_peak_lag=peak, scaled_final_lag=final,
                single_throughput=single_rate, scaled_throughput=scaled_rate,
                workload_creates_during_scaled_phase=b[-1]['load_created']-b[0]['load_created'],
                members_before=1,members_after=3, partitions=6, passed=True)
    Path(args.output).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('mode',choices=['sample','verify'])
    parser.add_argument('--duration',type=int,default=90)
    parser.add_argument('--members',type=int,default=1)
    parser.add_argument('--output',required=True)
    parser.add_argument('--single')
    parser.add_argument('--scaled')
    args=parser.parse_args()
    if args.mode=='sample':
        asyncio.run(sample(args))
    else:
        verify(args)
