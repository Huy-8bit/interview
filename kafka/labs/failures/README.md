# Failure scenarios

| Scenario | Script | Ghi chú |
|---|---|---|
| [broker_failure](broker_failure) | controlled shutdown dưới tải | 0 lỗi producer |
| [leader_failure](leader_failure) | kill -9 leader dưới tải | = lab 11 |
| [consumer_crash](consumer_crash) | crash consumer | lab 06B + lab 08 |
| [producer_restart](producer_restart) | SIGTERM vs SIGKILL producer | PID mới |
| [slow_consumer](slow_consumer) | consumer chậm | = lab 17 |
| [poison_message](poison_message) | poison / malformed | = lab 09 |
| [network_delay](network_delay) | tc netem 200ms | p99 22ms → 2.5s |
| [consumer_rebalance](consumer_rebalance) | rebalance | = lab 06 |
| [replica_out_of_sync](replica_out_of_sync) | iptables chặn replication | ISR shrink/expand |
| [hot_partition](hot_partition) | hot key | = lab 12 |

Network fault injection dùng `scripts/net-fault.sh`: chạy `tc`/`iptables` trong network namespace của broker qua
`docker run --cap-add NET_ADMIN --network container:<broker>` (image app có iproute2 + iptables). Docker Desktop (macOS) hỗ trợ netem/iptables trong VM Linux của nó.
