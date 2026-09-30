#!/bin/sh
set -eu
# Docker Engine/Desktop/OrbStack use different containerd socket locations.
# Keep real cAdvisor collection, choosing an existing socket rather than faking stats.
containerd_socket=${CADVISOR_CONTAINERD_SOCKET:-}
if [ -z "$containerd_socket" ]; then
  for candidate in /run/docker/containerd/containerd.sock /run/containerd/containerd.sock /run/desktop/containerd/containerd.sock; do
    if [ -S "$candidate" ]; then containerd_socket=$candidate; break; fi
  done
fi
if [ -n "$containerd_socket" ]; then
  echo "[startup][cadvisor] containerd socket: $containerd_socket"
  # Docker factory uses moby itself; keep generic containerd factory out of that namespace
  # so it cannot claim Docker cgroups before Docker labels/names are attached.
  exec /usr/bin/cadvisor --logtostderr --containerd="$containerd_socket" --containerd-namespace="${CADVISOR_CONTAINERD_NAMESPACE:-k8s.io}" "$@"
fi
exec /usr/bin/cadvisor --logtostderr "$@"
