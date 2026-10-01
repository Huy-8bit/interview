#!/usr/bin/env bash
# Records per partition (key distribution / hot partition).
#   ./scripts/partition-stats.sh orders
#   ./scripts/partition-stats.sh orders --snapshot     # remember current offsets
#   ./scripts/partition-stats.sh orders --since        # records produced since the snapshot
source "$(dirname "$0")/lib.sh"
topic="${1:-orders}"
case "${2:-}" in
  --snapshot) kcli stats -topic "$topic" -snapshot "/tmp/snap-$topic.json" && ok "snapshot saved" ;;
  --since)    kcli stats -topic "$topic" -since "/tmp/snap-$topic.json" ;;
  *)          kcli stats -topic "$topic" ;;
esac
