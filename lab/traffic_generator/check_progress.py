"""Read the worker's own metrics file; used by external fault-drill orchestration."""
import argparse
import json
import os
import time
from pathlib import Path


def read():
    return json.loads(Path(os.getenv("TRAFFIC_STATUS_FILE", "/tmp/traffic-generator-status.json")).read_text())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("counter")
    parser.add_argument("--delta", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--run-id")
    args = parser.parse_args()
    before = read()
    assert args.run_id is None or before["run_id"] == args.run_id, "Worker restarted since baseline"
    minimum = before["counts"].get(args.counter, 0) + args.delta
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        current = read()
        assert current["run_id"] == before["run_id"], "Worker restarted during the drill"
        assert time.time() - current["heartbeat_unix"] < 15, "Worker heartbeat stalled"
        if current["counts"].get(args.counter, 0) >= minimum:
            print(json.dumps(dict(counter=args.counter, before=before, after=current)))
            break
        time.sleep(0.5)
    else:
        raise SystemExit(f"No progress for {args.counter}: {current['counts']}")
