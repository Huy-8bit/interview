"""Change the running worker's request rate without restarting it; no flags prints the current rate."""
import argparse
import json
import time
from pathlib import Path
from uuid import uuid4

from pydantic import ValidationError

from traffic_generator.config import Config, RateControl

RATE_KEYS = ("state", "target_rps", "current_rps", "virtual_users", "active_virtual_users", "interval_ms", "control_version")


def read_status(config):
    status = json.loads(Path(config.status_file).read_text())
    return {key: status.get(key) for key in RATE_KEYS}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rps", type=float, help="Target HTTP attempts per second; 0 returns to a fixed pool")
    parser.add_argument("--virtual-users", type=int, help="Fixed pool size when rps is 0, starting pool size otherwise")
    parser.add_argument("--interval-ms", type=int, help="Pause after each flow")
    parser.add_argument("--timeout", type=float, default=5, help="Seconds to wait for the worker to apply the change")
    args = parser.parse_args()
    config = Config()
    changes = {key: value for key, value in dict(target_rps=args.rps, virtual_users=args.virtual_users, interval_ms=args.interval_ms).items() if value is not None}
    if changes:
        try:
            RateControl.model_validate(changes)
        except ValidationError as exc:
            raise SystemExit(str(exc)) from None
        if changes.get("virtual_users", 0) > config.max_virtual_users:
            raise SystemExit(f"virtual_users exceeds TRAFFIC_MAX_VIRTUAL_USERS={config.max_virtual_users}")
        version = str(uuid4())
        path = Path(config.control_file)
        temp = path.with_suffix(".tmp")
        temp.write_text(json.dumps(dict(version=version, **changes)))
        temp.replace(path)
        deadline = time.monotonic() + args.timeout
        while read_status(config)["control_version"] != version:
            if time.monotonic() > deadline:
                raise SystemExit("Worker did not apply the change; check `make traffic-logs` for rate_control_rejected")
            time.sleep(0.2)
    print(json.dumps(read_status(config)))
