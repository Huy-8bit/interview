# Data Model và vòng đời nghiệp vụ

[Mục lục](README.md) · [API Contracts](API_CONTRACTS.md) · [Consistency](CONSISTENCY_AND_FAILURES.md)

## 1. Quyền sở hữu và quan hệ giữa domain

```mermaid
flowchart LR
    %% diagram: domain-ownership
    vehicle["Vehicle in vehicle_db"] -.->|"logical reference: vehicle_id"| warranty["Warranty in warranty_db"]
    vehicle -.->|"logical reference: vehicle_id"| inspection["Inspection in inspection_db"]
    inspection -.->|"logical reference: inspection_id"| repair["Repair in repair_db"]
    vehicle -.->|"logical reference: vehicle_id"| repair
    repair -->|"Local foreign key"| notification["Notification in repair_db"]
```

[Xem sơ đồ SVG](diagrams/domain-ownership.svg)

Nét đứt chỉ quan hệ nghiệp vụ. Không có foreign key, JOIN hoặc cascade giữa database. Mỗi service có Alembic history và credentials riêng. Quan hệ notification → repair là FK thực trong cùng database.

Tất cả business IDs là UUID do ứng dụng sinh. `created_at`, `updated_at`, `completed_at` dùng TIMESTAMPTZ; API serialize ISO 8601. `updated_at` được cập nhật bởi SQLAlchemy, không có PostgreSQL trigger: SQL thủ công muốn thay timestamp phải cập nhật rõ ràng.

## 2. Vehicle database

```mermaid
erDiagram
    %% diagram: vehicle-erd
    vehicles {
        uuid id PK
        varchar vin UK "17 characters"
        varchar model
        varchar manufacturer
        integer production_year
        varchar owner_name
        varchar status "ACTIVE or INACTIVE"
        timestamptz created_at
        timestamptz updated_at
    }
```

[Xem sơ đồ SVG](diagrams/vehicle-erd.svg)

| Field | Validation/constraint | Ý nghĩa |
|---|---|---|
| vin | API regex `^[A-HJ-NPR-Z0-9]{17}$`; DB unique, varchar(17) | Danh tính nghiệp vụ bất biến; không có API sửa VIN |
| model, manufacturer | API 1–100 ký tự, trim; DB NOT NULL | Thông tin xe |
| production_year | API và DB 1886–2100 | Năm sản xuất |
| owner_name | API 1–200 ký tự, trim; DB NOT NULL | Customer cơ bản của lab |
| status | Default ACTIVE; DB check ACTIVE/INACTIVE | Trạng thái record xe |

`vehicles_vin_key` là unique constraint chống race giữa hai create request. `ix_vehicles_created(created_at,id)` hỗ trợ list ổn định. PATCH khóa row bằng FOR UPDATE, đổi dữ liệu và thêm vehicle.updated trong cùng transaction.

**Giới hạn:** INACTIVE hiện không tự expire warranty hay chặn inspection/repair. Những policy này chưa được implement. API không kiểm VIN check digit theo quy định từng thị trường.

Source: [model](../services/vehicle-service/app/models/vehicle.py), [schema](../services/vehicle-service/app/schemas/vehicle.py), [migration](../services/vehicle-service/migrations/versions/0001_initial.py).

## 3. Warranty database

```mermaid
erDiagram
    %% diagram: warranty-erd
    warranties {
        uuid id PK
        uuid vehicle_id "Logical reference only"
        varchar warranty_type "Part of composite unique key"
        date start_date
        date end_date
        varchar status "PENDING ACTIVE EXPIRED"
        timestamptz created_at
        timestamptz updated_at
    }
```

[Xem sơ đồ SVG](diagrams/warranty-erd.svg)

Unique key là **cặp** `(vehicle_id,warranty_type)`; từng cột riêng lẻ không unique. Mỗi xe có tối đa một DEFAULT, một EXTENDED và một POWERTRAIN theo API hiện tại. `end_date >= start_date` được kiểm ở API và DB.

| Loại | Nguồn tạo | Ngày bắt đầu/kết thúc | Trạng thái ban đầu |
|---|---|---|---|
| DEFAULT | vehicle.created handler | Ngày `event.occurred_at` → cộng DEFAULT_WARRANTY_DAYS | ACTIVE |
| EXTENDED/POWERTRAIN | POST /warranties | Do caller gửi; phải đã có warranty history của xe | PENDING |

`start_date/end_date` là date. Coverage xét ngày UTC hiện tại, inclusive cả hai đầu. DEFAULT cộng 1095 ngày là policy của lab, không phải phép cộng ba calendar years trong mọi năm nhuận.

```mermaid
stateDiagram-v2
    %% diagram: warranty-states
    direction LR
    [*] --> Pending: manual create
    [*] --> Active: default from event
    Pending: PENDING
    Active: ACTIVE
    Expired: EXPIRED
    Pending --> Active: activate within dates
    Pending --> Expired: manual or scheduled expiry
    Active --> Expired: manual or scheduled expiry
    Expired --> [*]
```

[Xem sơ đồ SVG](diagrams/warranty-states.svg)

Activate chỉ hợp lệ từ PENDING khi ngày hiện tại trong khoảng bảo hành. Manual expire được gọi cả trước end_date. Worker expiry mỗi 30 giây khóa tối đa 100 row PENDING/ACTIVE có `end_date < today`, chuyển EXPIRED và enqueue event; backlog lớn có thể cần nhiều chu kỳ.

Gọi lại transition với cùng trạng thái trả resource hiện có, không tạo event thứ hai. EXPIRED không activate lại. Coverage kiểm cả ngày nên không phụ thuộc worker expiry chạy đúng ngay thời điểm chuyển ngày.

Indexes: unique `(vehicle_id,warranty_type)`; `ix_warranties_coverage(vehicle_id,status,start_date,end_date)`; `ix_warranties_expiry(status,end_date)`. Query hiện tại lấy warranty history của xe rồi lọc coverage trong Python; index coverage có prefix vehicle_id hỗ trợ lookup đó.

Source: [model](../services/warranty-service/app/models/warranty.py), [business rules](../services/warranty-service/app/services/warranties.py).

## 4. Inspection database

```mermaid
erDiagram
    %% diagram: inspection-erd
    vehicle_references {
        uuid vehicle_id PK "No cross-database FK"
        boolean vehicle_seen
        boolean warranty_seen
        timestamptz created_at
        timestamptz updated_at
    }
    inspections {
        uuid id PK
        uuid vehicle_id "Logical reference only"
        varchar inspection_type
        varchar status
        varchar result "Nullable until complete"
        text failure_reason "Required for FAIL"
        text notes "Nullable"
        timestamptz created_at
        timestamptz updated_at
        timestamptz completed_at "Nullable until complete"
    }
```

[Xem sơ đồ SVG](diagrams/inspection-erd.svg)

Không vẽ cạnh FK giữa hai bảng vì migration không tạo FK đó. Business layer kiểm `vehicle_references.vehicle_seen=True` trước khi tạo inspection. `warranty_seen` chỉ là dấu đã nhận event, không phải điều kiện bắt buộc tạo inspection và không diễn tả warranty còn hiệu lực.

`inspection_type` qua API thuộc DELIVERY/PERIODIC/DIAGNOSTIC, default PERIODIC. Notes tối đa 4000 ký tự ở API; failure_reason 1–4000 và bắt buộc cho FAIL. DB dùng TEXT, vì vậy giới hạn độ dài tối đa nằm ở schema validation.

| Trạng thái | result | failure_reason | completed_at |
|---|---|---|---|
| PENDING/IN_PROGRESS | NULL | NULL | NULL |
| COMPLETED + PASS | PASS | NULL | NOT NULL |
| COMPLETED + FAIL | FAIL | NOT NULL, không rỗng/blank | NOT NULL |

Các quan hệ trong bảng trên được bảo vệ bởi check constraints. Index `(vehicle_id,created_at)` hỗ trợ truy vấn lịch sử xe. Completed inspection bất biến qua API; kiểm immutability ở business layer, không phải database trigger.

```mermaid
stateDiagram-v2
    %% diagram: inspection-states
    direction LR
    [*] --> Pending
    Pending: PENDING
    InProgress: IN_PROGRESS
    Passed: COMPLETED / PASS
    Failed: COMPLETED / FAIL
    Pending --> InProgress: start
    Pending --> Passed: complete PASS
    Pending --> Failed: complete FAIL
    InProgress --> Passed: complete PASS
    InProgress --> Failed: complete FAIL
    Passed --> [*]
    Failed --> [*]
```

[Xem sơ đồ SVG](diagrams/inspection-states.svg)

PASSED/FAILED không phải giá trị status lưu DB; sơ đồ dùng hai trạng thái kết hợp `status + result` để thể hiện hai kết quả terminal. Complete cùng result/reason và notes tương thích trả kết quả đã có; đổi kết quả sau complete trả 409.

Source: [model](../services/inspection-service/app/models/inspection.py), [projection handler](../services/inspection-service/app/messaging/handlers.py), [service](../services/inspection-service/app/services/inspections.py).

## 5. Repair database

```mermaid
erDiagram
    %% diagram: repair-erd
    repair_requests ||..o{ notifications : has
    repair_requests {
        uuid id PK
        uuid vehicle_id "Logical reference only"
        uuid inspection_id UK "One repair per inspection"
        boolean warranty_covered
        varchar status
        text description
        timestamptz created_at
        timestamptz updated_at
    }
    notifications {
        uuid id PK
        uuid vehicle_id "Logical reference only"
        uuid repair_id FK
        varchar channel
        text message
        varchar status
        timestamptz created_at
        timestamptz updated_at
    }
```

[Xem sơ đồ SVG](diagrams/repair-erd.svg)

ERD thể hiện cardinality schema: repair có thể có 0..N notifications, mỗi notification thuộc đúng một repair. Service hiện tại tạo đúng một LOG notification cùng transaction với repair. Unique `(repair_id,channel)` giới hạn mỗi channel một record; không có FK nào ép một repair phải có notification hoặc ép hai vehicle_id bằng nhau. Business layer thực hiện invariant đó.

`warranty_covered` NOT NULL là snapshot. Khi Warranty unavailable, lab rollback creation, không lưu NULL hoặc tự chọn false. Chưa lưu warranty_id/checked_at vào repair nên chưa đủ bằng chứng cho audit claim production. `description` do API nhập hoặc lấy từ failure_reason của event.

```mermaid
stateDiagram-v2
    %% diagram: repair-states
    direction LR
    [*] --> Open
    Open: OPEN
    InProgress: IN_PROGRESS
    Completed: COMPLETED
    Cancelled: CANCELLED
    Open --> InProgress: start repair
    Open --> Cancelled: cancel
    InProgress --> Completed: finish repair
    InProgress --> Cancelled: cancel
    Completed --> [*]
    Cancelled --> [*]
```

[Xem sơ đồ SVG](diagrams/repair-states.svg)

Không được nhảy OPEN → COMPLETED, không reopen terminal state. PATCH cùng trạng thái vẫn thành công. Chỉ creation phát repair.created; PATCH repair hiện không phát repair.updated/completed.

Notification channel/status hiện là LOG/SIMULATED. Đây là record mô phỏng, không phải acknowledgement từ provider. `notification_staged` log có thể xuất hiện trước outer transaction commit.

Source: [model](../services/repair-service/app/models/repair.py), [transaction](../services/repair-service/app/services/repairs.py).

## 6. Infrastructure tables trong từng database

```mermaid
erDiagram
    %% diagram: messaging-tables-erd
    outbox_events {
        bigint id PK "Identity sequence"
        varchar aggregate_id
        uuid event_id UK
        varchar event_type
        varchar topic
        jsonb payload
        varchar status
        integer attempts
        text last_error "Nullable"
        timestamptz created_at
        timestamptz next_attempt_at
        timestamptz published_at "Nullable"
    }
    processed_events {
        uuid event_id PK "Composite PK"
        varchar consumer_name PK "Composite PK"
        timestamptz processed_at
    }
    idempotency_records {
        varchar scope PK "Composite PK"
        varchar key_hash PK "Composite PK"
        varchar request_hash
        jsonb response "Filled before successful commit"
        integer status_code
        timestamptz created_at
    }
```

[Xem sơ đồ SVG](diagrams/messaging-tables-erd.svg)

Các bảng này không có FK với nhau. Event ID ở outbox nguồn và processed ledger downstream thuộc database khác nhau. `outbox_events.payload` chứa toàn bộ envelope; `id` chỉ phục vụ ordering/scan cục bộ, không phải Kafka offset. `aggregate_id` trong luồng hiện tại là vehicle ID cho cả bốn domain.

Outbox status PENDING/PUBLISHED, partial indexes trên pending `(next_attempt_at,id)` và `(aggregate_id,id)`. `attempts` đếm số publish attempt thất bại đã ghi lại, không phải số lần gửi thành công và không nhất thiết bao phủ crash trước DB commit.

Processed PK `(event_id,consumer_name)` giữ reservation chưa commit trong transaction rồi trở thành marker durable khi commit. Idempotency PK `(scope,key_hash)` giữ một payload hash và response snapshot; schema cho response nullable trong lúc xử lý nhưng application không commit reservation dở dang khi action lỗi.

`status_code` của idempotency ledger hiện mặc định 201; hai API consumer của helper đều là create trả 201. Helper hiện chỉ trả body, chưa tổng quát hóa replay mọi HTTP status/header.

Source: [models chung](../common/platform_common/models.py), [DDL v1](../common/platform_common/migration_v1.py).

## 7. Migrations, query và retention

Mỗi service chạy `alembic upgrade head` ở startup dưới PostgreSQL advisory lock. Application không dùng create_all khi startup; test fixture dùng schema tạm PostgreSQL riêng. Không chỉnh migration đã phát hành để triển khai feature mới; tạo revision kế tiếp.

```sh
docker compose exec vehicle-service alembic current
docker compose exec vehicle-service alembic check
docker compose exec postgres psql -U platform_admin -d warranty_db \
  -c "SELECT status,count(*) FROM warranties GROUP BY status;"
```

Danh sách vehicle/inspection/repair dùng limit/offset. Query ordering có thêm ID để ổn định khi timestamp trùng. Index inspections/repairs chưa chứa ID trong khóa index; PostgreSQL có thể cần sort phần bổ sung. Chưa claim tất cả list query đều index-only hoặc phù hợp hàng triệu row.

Retention hiện tại: không có cleanup cho business history, outbox/processed/idempotency ledger hay Redis generation keys. Đề xuất production phải xác định thời gian client retry, Kafka replay/backup restore horizon và audit requirements trước khi archive/delete. Không dùng TTL Redis thay cho retention policy của durable ledger.
