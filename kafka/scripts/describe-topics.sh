#!/usr/bin/env bash
# Topic / Partition / Leader / Replicas / ISR in a readable table.
#   ./scripts/describe-topics.sh                # all topics
#   ./scripts/describe-topics.sh orders         # one topic
#   ./scripts/describe-topics.sh orders --raw   # + the raw kafka-topics.sh output (shows ELR too)
source "$(dirname "$0")/lib.sh"
topic="${1:-}"
banner "Partition leaders / replicas / ISR ${topic:+(topic=$topic)}"
if [[ -n "$topic" ]]; then kcli topics -topic "$topic"; else kcli topics; fi
if [[ "${2:-}" == "--raw" ]]; then
  banner "kafka-topics.sh --describe ${topic}"
  kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe ${topic:+--topic "$topic"}
fi
