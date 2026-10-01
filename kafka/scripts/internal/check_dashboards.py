#!/usr/bin/env python3
"""Runs every Grafana panel query against Prometheus and reports which return no data."""
import glob, json, sys, urllib.parse, urllib.request
PROM = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:9090"
VARS = {"$group": "order-processing-group", "$topic": "orders"}
bad = 0
for f in sorted(glob.glob("monitoring/grafana/dashboards/*.json")):
    d = json.load(open(f))
    for p in d["panels"]:
        for t in p.get("targets", []):
            q = t["expr"]
            for k, v in VARS.items():
                q = q.replace(k, v)
            url = PROM + "/api/v1/query?" + urllib.parse.urlencode({"query": q})
            try:
                r = json.load(urllib.request.urlopen(url, timeout=10))
                n = len(r["data"]["result"]) if r["status"] == "success" else -1
            except Exception as e:  # noqa
                n = -1
            if n <= 0:
                bad += 1
            print(("OK  " if n > 0 else "NODATA" if n == 0 else "ERROR"), f"{n:3d}", d["uid"][:22].ljust(22), p["title"][:60])
print("panels-queries without data:", bad)
