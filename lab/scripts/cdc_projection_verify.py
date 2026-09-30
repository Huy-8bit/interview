"""Prove REST -> actual WAL CDC -> local projection -> FAIL -> coverage REST -> repair.
The optional delete is restricted to the single warranty this probe just created.
"""
import argparse
import asyncio
import json
import os
import time
from pathlib import Path
from uuid import uuid4

import httpx
from aiokafka import AIOKafkaConsumer

from scripts.postgres_cdc_verify import query as sql


async def wait_for(operation, predicate, timeout=60):
    deadline=time.monotonic()+timeout
    last=None
    while time.monotonic()<deadline:
        last=await operation()
        if predicate(last):
            return last
        await asyncio.sleep(.5)
    raise AssertionError(last)


async def run(output):
    topic='warranty-cdc.public.warranties'
    consumer=AIOKafkaConsumer(topic, bootstrap_servers=os.environ['KAFKA_BOOTSTRAP_SERVERS'],group_id=None,enable_auto_commit=False,auto_offset_reset='latest')
    try:
        await consumer.start()
        # Establish positions before creating the fresh business row.
        deadline=time.monotonic()+60
        while not consumer.assignment() and time.monotonic()<deadline:
            await consumer.getmany(timeout_ms=100)
        assert consumer.assignment(), 'CDC observer did not acquire partitions within 60s'
        await consumer.seek_to_end()
        async with httpx.AsyncClient(timeout=10) as http:
            cid=str(uuid4())
            headers={'X-Correlation-ID':cid}
            v=(await http.post('http://vehicle-service:8000/vehicles',headers=headers,json=dict(vin='LAB'+uuid4().hex[:14].upper(),manufacturer='Lab',model='CDC proof',production_year=2026,owner_name='Observability verification')))
            v.raise_for_status()
            vehicle=v.json()
            async def workflow():
                r=await http.get('http://inspection-service:8000/inspections/workflows/'+vehicle['id'])
                return r.json()
            ready=await wait_for(workflow,lambda r:r.get('status')=='READY')
            warranty_id=ready['warranty_id']
            r=await http.post('http://inspection-service:8000/inspections',headers={**headers,'Idempotency-Key':str(uuid4())},json={'vehicle_id':vehicle['id']})
            r.raise_for_status()
            inspection=r.json()
            assert inspection['warranty_id']==warranty_id
            r=await http.post('http://inspection-service:8000/inspections/'+inspection['id']+'/complete',headers=headers,json={'result':'FAIL','failure_reason':'CDC observability proof'})
            r.raise_for_status()
            async def repairs():
                r=await http.get('http://repair-service:8000/repairs',params={'inspection_id':inspection['id']})
                r.raise_for_status()
                return r.json()
            repair=(await wait_for(repairs,lambda r:len(r)==1))[0]
            assert repair['warranty_covered'] and repair['warranty_id']==warranty_id and repair['vehicle_id']==vehicle['id']
            r=await http.post('http://warranty-service:8000/warranties/'+warranty_id+'/expire',headers=headers)
            r.raise_for_status()
            expired=await wait_for(workflow,lambda r:any(w['warranty_id']==warranty_id and w['status']=='EXPIRED' for w in r.get('warranties',[])))
            deleted=await sql('DELETE FROM warranties WHERE id=CAST(:id AS uuid) AND vehicle_id=CAST(:vehicle AS uuid) RETURNING id',db='warranty_db',params={'id':warranty_id,'vehicle':vehicle['id']})
            assert len(deleted)==1
            removed=await wait_for(workflow,lambda r:r.get('status')=='WAITING_WARRANTY' and all(w['deleted'] for w in r['warranties']))
            records=[]
            deadline=time.monotonic()+40
            while time.monotonic()<deadline:
                batch=await consumer.getmany(timeout_ms=1000)
                for rows in batch.values():
                    for message in rows:
                        key=json.loads(message.key or b'{}')
                        if key.get('id')==warranty_id:
                            payload=json.loads(message.value) if message.value else None
                            records.append({'topic':message.topic,'partition':message.partition,'offset':message.offset,'key':key,'value':payload})
                operations={r['value']['op'] if r['value'] else 'tombstone' for r in records}
                if {'c','u','d','tombstone'}<=operations:
                    break
            assert {'c','u','d','tombstone'}<=operations, operations
            for record in records:
                value=record['value']
                if value:
                    assert value['source']['db']=='warranty_db' and value['source']['lsn']
                    row=value['before'] if value['op']=='d' else value['after']
                    assert row['vehicle_id']==vehicle['id'] and row['correlation_id']==cid
            proof={'correlation_id':cid,'vehicle_id':vehicle['id'],'warranty_id':warranty_id,'inspection_id':inspection['id'],'repair_id':repair['id'],
                   'ready':ready,'expired':expired,'deleted':removed,'records':records,'passed':True}
            Path(output).parent.mkdir(parents=True,exist_ok=True)
            Path(output).write_text(json.dumps(proof,indent=2)+'\n')
            print(json.dumps({k:v for k,v in proof.items() if k not in ('records','ready','expired','deleted')},indent=2))
    finally:
        await consumer.stop()


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    asyncio.run(run(args.output))
