"""Failure-path checks for the host launcher; these never contact a Docker daemon."""
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize("failure,expected", [
    ("init_exit", "FAILED (exit 9)"),
    ("init_timeout", "Timed out after 1s"),
    ("continuous_exit", "unexpectedly exited"),
])
def test_startup_stops_at_failed_gate_and_keeps_diagnostics(tmp_path, failure, expected):
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    shutil.copy(ROOT / "scripts/up.sh", scripts / "up.sh")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    docker = bin_dir / "docker"
    docker.write_text(f"#!{sys.executable}\n" + '''
import json
import os
import sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as out:
    out.write(json.dumps(args) + "\\n")
failure = os.environ["FAILURE"]
if args[:2] == ["compose", "ps"] and "-q" in args:
    print(args[-1])
elif args[:2] == ["compose", "up"] and "--help" in args:
    print("--wait-timeout")
elif args[0] == "inspect":
    service = args[-1]
    if ".Config.Env" in args[2]:
        print("TRAFFIC_MODE=continuous")
    elif service == "kafka-init" and failure == "init_exit":
        print("exited|9|none")
    elif service == "kafka-init" and failure == "init_timeout":
        print("running|0|none")
    elif service.endswith("init"):
        print("exited|0|none")
    elif service == "traffic-generator":
        print("exited|0|healthy")
    else:
        print("running|0|none")
''')
    docker.chmod(0o755)
    calls_path = tmp_path / "calls.jsonl"
    result = subprocess.run(
        ["bash", str(scripts / "up.sh")], cwd=tmp_path, capture_output=True, text=True, timeout=30,
        env={**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
             "STARTUP_TIMEOUT_SECONDS": "1", "FAILURE": failure, "CALLS": str(calls_path)},
    )
    assert result.returncode != 0
    assert expected in result.stdout
    assert "Startup completed" not in result.stdout
    assert "Inspect: docker compose logs --tail=100" in result.stdout
    log, = list((tmp_path / "artifacts/startup").glob("*/startup.log"))
    assert expected in log.read_text()
    # A failed init gate must prevent API/CDC/client startup commands entirely.
    calls = calls_path.read_text()
    if failure.startswith("init"):
        assert "vehicle-service" not in calls and "debezium-connect" not in calls
    assert '"down"' not in calls and '"rm"' not in calls
