# Kiểm chứng Kafka và Redis Cluster

[Mục lục](README.md) · [Thiết kế và command](CLUSTER_INFRASTRUCTURE.md) · [Báo cáo phiên bản đầu](VALIDATION.md)

Báo cáo này ghi nhận bước nâng Kafka/Redis, trước khi thêm PostgreSQL replication/CDC. Xem [báo cáo mới](POSTGRESQL_CDC_VALIDATION.md) cho database layer hiện tại.

Ngày thực hiện: **2026-09-30**. Docker trên macOS/ARM64, 8 GB RAM và 8 CPU cấp cho engine. Kafka 3.9.1, Redis 7.4.4, Python 3.12, redis-py 6.2.0, aiokafka 0.12.0.

## Topology được kiểm tra bằng lệnh thật

- Kafka: ba broker IDs 1/2/3 cùng cluster ID; static KRaft quorum ba voters. Tám business/DLQ topics có ba partitions/topic, mỗi partition ba replicas, ISR đủ ba khi khỏe. `min.insync.replicas=2` được đối chiếu với output topic description.
- Redis: `cluster_state:ok`, `cluster_slots_assigned=cluster_slots_ok=16384`, sáu known nodes, cluster_size=3, ba master và ba replica links UP.
- Kafka UI API báo online và brokerCount=3.
- Bốn application healthy; Repair được trả về một instance sau bài scale; LAB_MODE=false.

Output CLI được lưu cùng tài liệu: [Kafka topics](evidence/kafka-topics.txt), [KRaft quorum](evidence/kafka-quorum.txt), [Redis info](evidence/redis-info.txt), [Redis nodes](evidence/redis-nodes.txt), [topology và assignments cuối lượt](evidence/cluster-final.json). Đây là snapshot tại thời điểm kiểm tra, không phải mapping leader/master cố định.

## Bộ test và kiểm tra code

**32 tests pass** sau các thay đổi cluster/recovery: Vehicle 5, Warranty 3, Inspection 2, Repair 2, root suite 20 (unit 7 + integration 13). Có regression cho Redis Cluster discovery unavailable và phân biệt consumer idle với fetcher có backlog bị kẹt. Các service/integration tests dùng PostgreSQL, Redis Cluster và Kafka Cluster thật; ba bài unit progress dùng mock giao diện consumer để điều khiển trạng thái idle/stalled.

Ruff pass cho shared code, bốn service, scripts và tests. Shell scripts qua syntax check; Compose config hợp lệ. 29 Mermaid diagrams đã render SVG, các diagram cluster đã được xem preview; local links và manifest source/artifacts được kiểm tra bằng `make docs-check`.

## Bằng chứng node failure và consumer scale

Script `cluster_drills.sh` giữ producer/consumer hoặc Redis client mở **trước** khi hard-stop node, chờ recovery, kiểm end-to-end workflow khi node còn down, rồi start lại và chờ topology đầy đủ. Snapshot/result JSON: [cluster-drills.json](evidence/cluster-drills.json).

Các trường hợp đã chạy:

| Tình huống | Điều kiện pass |
|---|---|
| Dừng Kafka controller/broker | DescribeQuorum xác nhận LeaderId đổi; producer và consumer tiếp tục với cùng instances; còn hai live brokers/ISR; workflow hoàn tất |
| Dừng partition leader | Metadata/leader đổi; ACK mới và consumer nhận đúng event ID; không thay bootstrap list |
| Restart broker | Cả tám topics trở lại RF=3, ISR=3 |
| Dừng Redis replica | Cluster vẫn OK, cache HIT và idempotency còn hoạt động |
| Dừng Redis master | Replica đúng cặp promote; API GET vẫn 200, client route key sang slot owner mới |
| Start Redis node cũ | Trở lại 3 master + 3 replica, replication links UP; không reset slots |
| Scale Repair 1 → 3 → 1 | Group Stable; mỗi partition có một owner; khi ba member thì mỗi member một partition |

Lượt cuối ghi nhận active KRaft leader **3 → 2**, epoch **7 → 9**, sau khi SIGKILL `kafka-3`: [quorum trước](evidence/kraft-election-before.txt), [quorum sau khi dừng node](evidence/kraft-election-after.txt). Giá trị này lấy từ DescribeQuorum; `MetadataResponse.controller_id` trong snapshot chỉ là admin forwarding hint. Redis master `redis-3` được thay bằng replica `redis-4`; các GET trong thời gian recovery đều trả HTTP 200, sau đó kiểm lại cache HIT/invalidation và cùng inspection khi retry Idempotency-Key.

Thời gian trong JSON là phép đo của một lượt trên máy local, tính từ signal sau khi container đã dừng đến khi các kiểm tra probe hoàn tất. Chúng gồm chi phí retry/API/verification, **không phải SLO hoặc benchmark failover**.

## Full-cluster outage và các lỗi đã xử lý

- Dừng cả sáu Redis node: cache GET dùng PostgreSQL, cùng Idempotency-Key trả cùng inspection; start lại cả sáu node và readiness phục hồi. Đã sửa xử lý `RedisClusterException` khi tất cả startup nodes mất kết nối; exception này không kế thừa `RedisError` trong phiên bản client đang dùng.
- Dừng cả ba Kafka broker: API vẫn commit vehicle/outbox PENDING, có publish attempts thất bại; start lại, outbox tiếp tục và workflow Vehicle → Warranty → Inspection FAIL → Repair hoàn tất.
- Đã xử lý trường hợp consumer có heartbeat nhưng fetch không tiến triển sau cluster restart bằng bounded getmany polling, deadline start/fetch/offset commit và kiểm backlog khi poll rỗng kéo dài. Recovery probe hiện xác nhận workflow downstream, không chỉ readiness/source outbox.
- Chạy lại Redis init sau promotion: script nhận cluster hiện hữu, giữ role/slots, xác nhận đủ replication links.

## Dữ liệu và giới hạn

441 Kafka records của stack cũ đã được xuất rồi nhập vào cluster mới, giữ key/value/partition/offset/timestamp. PostgreSQL giữ nguyên. Hai container standalone đã dừng và bỏ; volumes `vehicle-platform-lab_kafka-data` và `vehicle-platform-lab_redis-data` được giữ để tránh xóa dữ liệu cũ. Không chạy `down -v`.

Các bài thử để lại dữ liệu mẫu, operational probe events và evidence trong `artifacts/cluster-drills/`. Kafka DLQ cũ cũng được giữ; consumer ledger ngăn chạy lại các event đã commit khi chuyển cluster.

Chưa kiểm chứng lỗi host/AZ, mất đồng thời master và replica cùng slot, network partition/asymmetric partition, disk corruption, online resharding, load/soak hoặc backup restore. Hệ thống vẫn dùng một PostgreSQL instance và một Docker host. Redis async replication/lease không cung cấp fencing hoặc exactly-once toàn hệ thống.
