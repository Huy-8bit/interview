"""Docker healthcheck: the worker parent serves metrics and has started consuming."""
import os
import urllib.request

if __name__ == "__main__":
    port = os.getenv("REPORT_METRICS_PORT", "9808")
    body = urllib.request.urlopen(f"http://127.0.0.1:{port}/metrics", timeout=3).read().decode()
    ready = any(line.startswith("background_worker_ready{") and line.rstrip().endswith(" 1.0") for line in body.splitlines())
    raise SystemExit(0 if ready else 1)
