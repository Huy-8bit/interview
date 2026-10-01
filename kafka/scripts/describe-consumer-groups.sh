#!/usr/bin/env bash
# Consumer groups: members, assignment, committed offsets, lag.
#   ./scripts/describe-consumer-groups.sh                          # every group (summary + details)
#   ./scripts/describe-consumer-groups.sh order-processing-group  # one group
#   ./scripts/describe-consumer-groups.sh order-processing-group --raw   # + kafka-consumer-groups.sh
source "$(dirname "$0")/lib.sh"
group="${1:-}"
if [[ -z "$group" ]]; then
  banner "Consumer groups"
  kcli groups
  for g in $(kcli groups | awk 'NR>1 {print $1}'); do echo; kcli group -group "$g"; done
  exit 0
fi
banner "Group $group"
kcli group -group "$group"
if [[ "${2:-}" == "--raw" ]]; then
  banner "kafka-consumer-groups.sh --describe --group $group (--members --verbose)"
  kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --group "$group"
  kt kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --group "$group" --members --verbose
fi
