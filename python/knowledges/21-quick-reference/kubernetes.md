# Kubernetes Cheatsheet

- Deployment quản ReplicaSet/Pod; Service tạo stable discovery; Ingress/Gateway route L7.
- Request dùng scheduling/HPA denominator; CPU limit có throttling, memory limit có OOMKill.
- Readiness: nhận traffic? Liveness: process cần restart? Startup: app chưa khởi động xong?
- HPA scale compute, không scale DB capacity; queue age tốt hơn CPU cho worker.
- Rolling update cần maxSurge/maxUnavailable, PDB, readiness và graceful termination.
- Debug: event → pod status/restart → logs previous → resource/throttle → endpoints/network/DNS.
