#!/usr/bin/env bash
# Create (or re-apply configs of) every topic in kafka/topics/topics.conf.
#   ./scripts/create-topics.sh                 # all topics
#   ./scripts/create-topics.sh orders payments # only these
source "$(dirname "$0")/lib.sh"
banner "Applying kafka/topics/topics.conf"
ONLY_TOPICS="$*" docker compose run --rm -e ONLY_TOPICS="$*" kafka-init
