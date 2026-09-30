# Diagram Gallery

[Mục lục tài liệu](../README.md). SVG được render từ Mermaid trong tài liệu gốc.

Chạy `make docs-render` để cập nhật; file này được tạo tự động.

| Sơ đồ | Tài liệu | SVG | Mermaid source |
|---|---|---|---|
| 2. WHY KAFKA HERE? WHY RABBITMQ HERE? | [BACKGROUND_TASKS.md](../BACKGROUND_TASKS.md) | [Xem SVG](kafka-vs-rabbitmq-roles.svg) | [Source](sources/kafka-vs-rabbitmq-roles.mmd) |
| 3. Luồng xử lý | [BACKGROUND_TASKS.md](../BACKGROUND_TASKS.md) | [Xem SVG](report-task-lifecycle.svg) | [Source](sources/report-task-lifecycle.mmd) |
| 6. ACK, redelivery và timeout | [BACKGROUND_TASKS.md](../BACKGROUND_TASKS.md) | [Xem SVG](report-task-ack.svg) | [Source](sources/report-task-ack.mmd) |
| 1. Topology đang triển khai | [CLUSTER_INFRASTRUCTURE.md](../CLUSTER_INFRASTRUCTURE.md) | [Xem SVG](clustered-infrastructure.svg) | [Source](sources/clustered-infrastructure.mmd) |
| 2. Kafka KRaft, replication và quorum | [CLUSTER_INFRASTRUCTURE.md](../CLUSTER_INFRASTRUCTURE.md) | [Xem SVG](kafka-leader-failover.svg) | [Source](sources/kafka-leader-failover.mmd) |
| Producer và consumer | [CLUSTER_INFRASTRUCTURE.md](../CLUSTER_INFRASTRUCTURE.md) | [Xem SVG](consumer-partition-rebalance.svg) | [Source](sources/consumer-partition-rebalance.mmd) |
| Failover và correctness | [CLUSTER_INFRASTRUCTURE.md](../CLUSTER_INFRASTRUCTURE.md) | [Xem SVG](redis-master-failover.svg) | [Source](sources/redis-master-failover.mmd) |
| 2. Transactional outbox và các cửa sổ crash | [CONSISTENCY_AND_FAILURES.md](../CONSISTENCY_AND_FAILURES.md) | [Xem SVG](outbox-reliability.svg) | [Source](sources/outbox-reliability.mmd) |
| 3. Idempotent consumer và offset discipline | [CONSISTENCY_AND_FAILURES.md](../CONSISTENCY_AND_FAILURES.md) | [Xem SVG](consumer-processing.svg) | [Source](sources/consumer-processing.mmd) |
| 9. Recovery khác compensation | [CONSISTENCY_AND_FAILURES.md](../CONSISTENCY_AND_FAILURES.md) | [Xem SVG](recovery-strategy.svg) | [Source](sources/recovery-strategy.mmd) |
| 1. Quyền sở hữu và quan hệ giữa domain | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](domain-ownership.svg) | [Source](sources/domain-ownership.mmd) |
| 2. Vehicle database | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](vehicle-erd.svg) | [Source](sources/vehicle-erd.mmd) |
| 3. Warranty database | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](warranty-erd.svg) | [Source](sources/warranty-erd.mmd) |
| 3. Warranty database | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](warranty-states.svg) | [Source](sources/warranty-states.mmd) |
| 4. Inspection database | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](inspection-erd.svg) | [Source](sources/inspection-erd.mmd) |
| 4. Inspection database | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](inspection-states.svg) | [Source](sources/inspection-states.mmd) |
| 5. Repair database | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](repair-erd.svg) | [Source](sources/repair-erd.mmd) |
| 5. Repair database | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](repair-states.svg) | [Source](sources/repair-states.mmd) |
| 6. Infrastructure tables trong từng database | [DATA_MODEL.md](../DATA_MODEL.md) | [Xem SVG](messaging-tables-erd.svg) | [Source](sources/messaging-tables-erd.mmd) |
| 1. Topology và subscriptions | [EVENT_CONTRACTS.md](../EVENT_CONTRACTS.md) | [Xem SVG](event-topology.svg) | [Source](sources/event-topology.mmd) |
| 2. Architecture và metrics pipeline | [OBSERVABILITY.md](../OBSERVABILITY.md) | [Xem SVG](observable-business-flow.svg) | [Source](sources/observable-business-flow.mmd) |
| 2. Architecture và metrics pipeline | [OBSERVABILITY.md](../OBSERVABILITY.md) | [Xem SVG](metrics-pipeline.svg) | [Source](sources/metrics-pipeline.mmd) |
| 3. Hai đường dữ liệu chuẩn bị Inspection | [OBSERVABILITY.md](../OBSERVABILITY.md) | [Xem SVG](inspection-two-input-readiness.svg) | [Source](sources/inspection-two-input-readiness.mmd) |
| 4. Quy trình điều tra một inspection FAIL chưa có repair | [OPERATIONS.md](../OPERATIONS.md) | [Xem SVG](incident-triage.svg) | [Source](sources/incident-triage.mmd) |
| 1. Thiết kế đang chạy | [POSTGRESQL_CDC.md](../POSTGRESQL_CDC.md) | [Xem SVG](postgres-cdc-infrastructure.svg) | [Source](sources/postgres-cdc-infrastructure.mmd) |
| Thay bằng ID trả về từ POST /vehicles | [POSTGRESQL_CDC.md](../POSTGRESQL_CDC.md) | [Xem SVG](postgres-replica-lag.svg) | [Source](sources/postgres-replica-lag.mmd) |
| 6. Initial snapshot và continuous CDC | [POSTGRESQL_CDC.md](../POSTGRESQL_CDC.md) | [Xem SVG](debezium-snapshot-recovery.svg) | [Source](sources/debezium-snapshot-recovery.mmd) |
| 8. Hai đường phát sự kiện độc lập | [POSTGRESQL_CDC.md](../POSTGRESQL_CDC.md) | [Xem SVG](outbox-and-cdc.svg) | [Source](sources/outbox-and-cdc.mmd) |
| 1. Tạo vehicle → default warranty → projection | [REQUEST_FLOWS.md](../REQUEST_FLOWS.md) | [Xem SVG](vehicle-creation-sequence.svg) | [Source](sources/vehicle-creation-sequence.mmd) |
| 2. Complete FAIL → coverage REST → repair và notification | [REQUEST_FLOWS.md](../REQUEST_FLOWS.md) | [Xem SVG](inspection-repair-sequence.svg) | [Source](sources/inspection-repair-sequence.mmd) |
| 3. Hai API create request cùng Idempotency-Key | [REQUEST_FLOWS.md](../REQUEST_FLOWS.md) | [Xem SVG](api-idempotency-sequence.svg) | [Source](sources/api-idempotency-sequence.mmd) |
| 4. Hai consumer task cùng event ID | [REQUEST_FLOWS.md](../REQUEST_FLOWS.md) | [Xem SVG](consumer-concurrency-sequence.svg) | [Source](sources/consumer-concurrency-sequence.mmd) |
| 5. Cache fill chạy đua với PATCH | [REQUEST_FLOWS.md](../REQUEST_FLOWS.md) | [Xem SVG](cache-generation-sequence.svg) | [Source](sources/cache-generation-sequence.mmd) |
| 6. Warranty expiry tự động | [REQUEST_FLOWS.md](../REQUEST_FLOWS.md) | [Xem SVG](warranty-expiry-sequence.svg) | [Source](sources/warranty-expiry-sequence.mmd) |
| 1. Bài toán và phạm vi | [SYSTEM_DESIGN.md](../SYSTEM_DESIGN.md) | [Xem SVG](system-context.svg) | [Source](sources/system-context.mmd) |
| 3. High-level design | [SYSTEM_DESIGN.md](../SYSTEM_DESIGN.md) | [Xem SVG](system-containers.svg) | [Source](sources/system-containers.mmd) |
| 4. Low-level design trong một application | [SYSTEM_DESIGN.md](../SYSTEM_DESIGN.md) | [Xem SVG](service-components.svg) | [Source](sources/service-components.mmd) |
| 6. Deployment và lifecycle | [SYSTEM_DESIGN.md](../SYSTEM_DESIGN.md) | [Xem SVG](startup-dependencies.svg) | [Source](sources/startup-dependencies.mmd) |
| 9. Hướng production — chưa triển khai | [SYSTEM_DESIGN.md](../SYSTEM_DESIGN.md) | [Xem SVG](production-target.svg) | [Source](sources/production-target.mmd) |
| 1. Mục tiêu và ranh giới | [TRAFFIC_GENERATOR.md](../TRAFFIC_GENERATOR.md) | [Xem SVG](traffic-architecture.svg) | [Source](sources/traffic-architecture.mmd) |
| 2. Một lifecycle | [TRAFFIC_GENERATOR.md](../TRAFFIC_GENERATOR.md) | [Xem SVG](traffic-lifecycle.svg) | [Source](sources/traffic-lifecycle.mmd) |
| 3. Retry, idempotency và timeout | [TRAFFIC_GENERATOR.md](../TRAFFIC_GENERATOR.md) | [Xem SVG](traffic-retry.svg) | [Source](sources/traffic-retry.mmd) |
