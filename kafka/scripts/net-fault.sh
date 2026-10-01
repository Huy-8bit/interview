#!/usr/bin/env bash
# Network fault injection inside a broker's network namespace (tc netem / iptables).
#   ./scripts/net-fault.sh delay 3 300ms         # add 300ms latency to every packet leaving kafka-3
#   ./scripts/net-fault.sh delay-to 1 toolbox 1500ms   # delay only kafka-1 -> toolbox packets (responses)
#   ./scripts/net-fault.sh block-replication 3   # kafka-3 can't fetch from leaders (replication port 29092), still heartbeats the controller
#   ./scripts/net-fault.sh clear 3               # remove every rule
#   ./scripts/net-fault.sh show 3
source "$(dirname "$0")/lib.sh"
action="${1:?action}"; id="${2:?broker id}"; svc="kafka-$id"
case "$action" in
  delay)
    in_broker_netns "$svc" tc qdisc replace dev eth0 root netem delay "${3:-300ms}"
    ok "$svc: all egress delayed by ${3:-300ms}" ;;
  delay-to)
    target="${3:?target service}"; d="${4:-1500ms}"
    ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(cid "$target")")"
    in_broker_netns "$svc" sh -c "tc qdisc del dev eth0 root 2>/dev/null; \
      tc qdisc add dev eth0 root handle 1: prio && \
      tc qdisc add dev eth0 parent 1:3 handle 30: netem delay $d && \
      tc filter add dev eth0 protocol ip parent 1:0 prio 3 u32 match ip dst $ip/32 flowid 1:3"
    ok "$svc: packets to $target ($ip) delayed by $d" ;;
  block-replication)
    for other in 1 2 3; do
      [[ "$other" == "$id" ]] && continue
      [[ -z "$(cid "kafka-$other")" ]] && continue   # broker not running: nothing to block
      ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(cid "kafka-$other")")"
      in_broker_netns "$svc" iptables -A OUTPUT -p tcp -d "$ip" --dport 29092 -j DROP
    done
    ok "$svc: outgoing connections to other brokers' INTERNAL listener (29092) dropped; CONTROLLER (29093) still open" ;;
  clear)
    in_broker_netns "$svc" sh -c 'tc qdisc del dev eth0 root 2>/dev/null; iptables -F OUTPUT; true'
    ok "$svc: network rules cleared" ;;
  show)
    in_broker_netns "$svc" sh -c 'echo "# tc"; tc qdisc show dev eth0; echo "# iptables OUTPUT"; iptables -S OUTPUT' ;;
  *) die "unknown action $action" ;;
esac
