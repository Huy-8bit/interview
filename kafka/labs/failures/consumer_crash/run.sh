#!/usr/bin/env bash
# Consumer crash: (1) detection = session timeout (lab 06 part B), (2) what happens to
# in-flight records = duplicate or loss depending on commit order (lab 08).
set -e
PARTS="B" "$(dirname "$0")/../../06_rebalancing/run.sh"
"$(dirname "$0")/../../08_delivery_semantics/run.sh"
