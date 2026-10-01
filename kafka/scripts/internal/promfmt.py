#!/usr/bin/env python3
"""Pretty-print a Prometheus instant query JSON response (stdin)."""
import json
import sys

res = json.load(sys.stdin)["data"]["result"]
for x in res[:12]:
    labels = ",".join(f"{k}={v}" for k, v in x["metric"].items() if k not in ("__name__", "job"))
    print(f"    {labels or '(total)':60s} {float(x['value'][1]):.2f}")
if not res:
    print("    (no data)")
