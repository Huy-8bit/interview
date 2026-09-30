#!/bin/sh
set -eu
# All nodes and CLI tools must share one Erlang cookie to form a cluster.
# The entrypoint then fixes ownership and drops privileges to the rabbitmq user.
cookie=/var/lib/rabbitmq/.erlang.cookie
umask 077
printf '%s' "$RABBITMQ_CLUSTER_COOKIE" > "$cookie"
chmod 400 "$cookie"
exec docker-entrypoint.sh rabbitmq-server
