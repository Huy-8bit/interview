# Diagram Gallery

[Mục lục tài liệu](../README.md). SVG được render từ Mermaid trong tài liệu gốc.

Chạy `make docs-render` để cập nhật; file này được tạo tự động.

| Sơ đồ | Tài liệu | SVG | Mermaid source |
|---|---|---|---|
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
| 4. Quy trình điều tra một inspection FAIL chưa có repair | [OPERATIONS.md](../OPERATIONS.md) | [Xem SVG](incident-triage.svg) | [Source](sources/incident-triage.mmd) |
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
