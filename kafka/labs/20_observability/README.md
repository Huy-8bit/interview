# Lab 20 — Observability tour

**Mục tiêu**: biết mỗi câu hỏi vận hành thì nhìn metric/dashboard nào.
**Đọc trước**: [docs/20](../../docs/20-monitoring.md)

## Chạy
```bash
./labs/20_observability/run.sh
python3 scripts/internal/check_dashboards.py      # chạy mọi query của 6 dashboard
```
Mở: Grafana http://localhost:3000 (admin/admin), Prometheus http://localhost:9090 (Alerts), Kafka UI http://localhost:8080.

## Quan sát (kết quả thật)
```text
13 target up (3 broker JMX, lag-exporter, 2 producer, 7 consumer) ; 5 down = consumer profile "scale" không chạy (đúng)
active controller: broker=kafka-3 ; URP 0 ; offline 0 ; Produce p99 3–5ms
6 dashboards provisioned ; Kafka UI: cluster kafka-lab status ONLINE brokers 3 online partitions 175
alert ConsumerLagGrowing firing -> do group debug bỏ quên (lag 238k) -> reset-lab đã dọn
```

## Bài tập
Chạy `./labs/11_broker_failure/run.sh` trong khi mở "Partition / Replication Health" và "Producer Performance": chỉ ra thời điểm leader đổi, ISR shrink/expand, latency spike.
