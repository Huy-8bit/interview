import json
import os
import time
from pathlib import Path

if __name__ == "__main__":
    try:
        status = json.loads(Path(os.getenv("TRAFFIC_STATUS_FILE", "/tmp/traffic-generator-status.json")).read_text())
        healthy = status["state"] in ("running", "disabled") and time.time() - status["heartbeat_unix"] < 15
    except (OSError, ValueError, KeyError):
        healthy = False
    raise SystemExit(0 if healthy else 1)
