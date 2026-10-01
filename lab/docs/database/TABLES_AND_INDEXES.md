# Bảng, cột và chỉ mục

Schema dưới đây được tổng hợp từ các migration hiện có và script khởi tạo CDC. Mọi bảng được tạo trong schema PostgreSQL `public`. Mỗi database có bảng `alembic_version` để ghi revision đã áp dụng. Hàm `upgrade_common()` được gọi bởi migration đầu tiên của từng service và tạo ba bảng hỗ trợ gửi/nhận message trong từng database.

Trong các bảng cột, `NULL` nghĩa là cột cho phép không có giá trị; `NOT NULL` nghĩa là phải có giá trị. Giá trị mặc định có thể do PostgreSQL đặt hoặc do Python/SQLAlchemy đặt trước khi gửi lệnh. `UUID` là mã định danh 128-bit; `JSONB` là JSON được PostgreSQL lưu theo dạng có thể truy vấn; `BYTEA` là dữ liệu nhị phân; `TIMESTAMPTZ` là thời điểm có thông tin múi giờ; `TEXT` là chuỗi dài không giới hạn bởi độ dài khai báo. Những từ viết tắt này được mở rộng ở đây; tên kiểu dữ liệu vẫn giữ đúng cú pháp PostgreSQL.

## 1. Danh sách bảng theo database

| Database | Tables |
|---|---|
| `vehicle_db` | `alembic_version`, `cdc_heartbeat`, `outbox_events`, `processed_events`, `idempotency_records`, `vehicles`, `warranty_provision_requests` |
| `warranty_db` | `alembic_version`, `cdc_heartbeat`, `outbox_events`, `processed_events`, `idempotency_records`, `warranties` |
| `inspection_db` | `alembic_version`, `cdc_heartbeat`, `outbox_events`, `processed_events`, `idempotency_records`, `vehicle_references`, `vehicle_warranty_projection`, `inspections`, `inspection_reports` |
| `repair_db` | `alembic_version`, `cdc_heartbeat`, `outbox_events`, `processed_events`, `idempotency_records`, `repair_requests`, `notifications` |

`cdc_heartbeat` được tạo bởi [init-cdc.sh](../../infrastructure/postgres/init-cdc.sh), nằm ngoài lịch sử migration của ứng dụng. Debezium publication hiện đọc một bảng nghiệp vụ chính trong mỗi database cùng bảng heartbeat; outbox được publisher ứng dụng đọc riêng, không được Debezium capture. Hàng đợi RabbitMQ tồn tại trong broker RabbitMQ, không phải trong PostgreSQL.

## 2. Bảng dùng chung (một bản trong mỗi database)

| Table | Columns và purpose | Keys, constraints, indexes |
|---|---|---|
| `alembic_version` | `version_num`; revision đã apply trong DB đó | PK trên version marker do Alembic quản lý |
| `cdc_heartbeat` | `id`, `updated_at`; heartbeat Debezium | PK `id`; index khác không khai báo |
| `outbox_events` | `id`, `aggregate_id`, `event_id`, `event_type`, `topic`, `payload JSONB`, `status`, `attempts`, `last_error`, `created_at`, `next_attempt_at`, `published_at` | PK `id`; unique `event_id`; check status; partial indexes `ix_outbox_pending(next_attempt_at,id) WHERE status='PENDING'` và `ix_outbox_aggregate(aggregate_id,id) WHERE status='PENDING'` |
| `processed_events` | `event_id`, `consumer_name`, `processed_at`; durable dedupe marker | Composite PK `(event_id,consumer_name)`; secondary index không khai báo |
| `idempotency_records` | `scope`, `key_hash`, `request_hash`, `response JSONB`, `status_code`, `created_at`; API retry result | Composite PK `(scope,key_hash)`; DDL còn khai báo unique cùng cặp `uq_idempotency_scope_key`, tạo uniqueness/index trùng với PK |

`outbox_events.id` là thứ tự scan cục bộ, không phải Kafka offset. `processed_events` phân biệt consumer group/name. Redis không thay thế hai durable ledgers này.

### Vai trò và hệ quả của các bảng dùng chung

- `outbox_events` biến ý định phát event thành dữ liệu bền vững. `payload` chứa envelope JSONB; `event_id` giữ nguyên qua lần retry. Chỉ row PENDING được publisher quét. `aggregate_id` cùng `id` giữ thứ tự các event của một aggregate, nhưng có thể tạo head-of-line blocking nếu event cũ liên tục lỗi.
- `processed_events` là dấu đã xử lý của một event trong một namespace consumer. Khóa chính ghép ngăn hai delivery cùng event và cùng consumer cùng commit tác động. Đổi consumer group có thể tạo namespace mới và cho phép replay lại.
- `idempotency_records` giữ fingerprint của request và response JSON để POST retry nhận cùng kết quả. `response` có thể NULL trong transaction chưa hoàn thành nhưng helper không chủ ý commit reservation lỗi. Khóa `scope` tách hành vi API, còn `key_hash` không lưu khóa thô do client gửi.
- Composite primary key đã tạo unique index cần thiết cho `idempotency_records`; DDL thêm unique constraint cùng cặp là dư thừa về tính duy nhất và thường sinh thêm index vật lý. Đây là hiện trạng được ghi nhận, chưa phải thay đổi schema đề xuất áp dụng ngay.
- PostgreSQL tự tạo sequence/identity cho `outbox_events.id` và index cho khóa chính/unique. Bảng `alembic_version` do Alembic quản lý; `cdc_heartbeat` do script hạ tầng tạo.

## 3. `vehicle_db`

| Table | Cột nghiệp vụ chính | Keys, constraints và indexes |
|---|---|---|
| `vehicles` | `id`, `vin`, `model`, `manufacturer`, `production_year`, `owner_name`, `status`, `simulation_run_id`, timestamps | PK `id`; unique `vin` (`vehicles_vin_key`); checks status ACTIVE/INACTIVE và year 1886–2100; `ix_vehicles_created(created_at,id)` |
| `warranty_provision_requests` | `vehicle_id`, `correlation_id`, `status`, `attempts`, `warranty_id`, `last_error`, `next_attempt_at`, timestamps | PK `vehicle_id`; `ix_warranty_provision_requests_status(status)`; không FK sang `warranty_db` |

`simulation_run_id` được thêm bởi migration 0002; warranty provision table được thêm bởi 0003. `vin` exact-match dùng unique index. Provision worker lọc status/due time, tùy chọn vehicle ID, rồi order theo `created_at`; index hiện có chỉ theo status, chưa composite theo due/order.

### Ý nghĩa cột

| Table | Cột | Ý nghĩa, nullability và quy tắc |
|---|---|---|
| `vehicles` | `id UUID` | Khóa chính do ứng dụng sinh; không null. |
| | `vin VARCHAR(17)` | VIN 17 ký tự, không null, duy nhất; API không cho sửa sau khi tạo. |
| | `model VARCHAR(100)`, `manufacturer VARCHAR(100)` | Thông tin mô tả, không null. |
| | `production_year INTEGER` | Không null; CHECK từ 1886 đến 2100. |
| | `owner_name VARCHAR(200)` | Tên chủ xe trong phạm vi lab, không null. |
| | `status VARCHAR(20)` | Mặc định ACTIVE; CHECK chỉ nhận ACTIVE/INACTIVE. |
| | `simulation_run_id UUID` | Cho phép NULL; đánh dấu row thuộc lần chạy traffic nào để giới hạn quyền xóa mô phỏng. |
| | `created_at`, `updated_at TIMESTAMPTZ` | Không null, mặc định thời gian DB; ORM cập nhật `updated_at` khi sửa row. |
| `warranty_provision_requests` | `vehicle_id UUID` | Khóa chính và định danh lệnh provision; không có khóa ngoại sang database khác. |
| | `correlation_id VARCHAR(128)` | Mã liên kết log/REST/CDC, không null. |
| | `status VARCHAR(20)` | Mặc định PENDING; migration không có CHECK liệt kê trạng thái hợp lệ. Code hiện đặt PENDING hoặc DELIVERED. |
| | `attempts INTEGER` | Mặc định 0; số lần gửi lỗi đã được ghi nhận. |
| | `warranty_id UUID` | Cho phép NULL trước khi REST thành công; logical reference tới warranty database. |
| | `last_error VARCHAR(100)` | Cho phép NULL; lưu loại exception, không lưu URL/credential. |
| | `next_attempt_at TIMESTAMPTZ` | Thời điểm sớm nhất thử gửi lại; mặc định thời gian hiện tại. |
| | `created_at`, `updated_at TIMESTAMPTZ` | Dùng để theo dõi thời điểm tạo/cập nhật lệnh. |

Source: [vehicle model](../../services/vehicle-service/app/models/vehicle.py), [vehicle migrations](../../services/vehicle-service/migrations/versions/).

## 4. `warranty_db`

| Table | Cột nghiệp vụ chính | Keys, constraints và indexes |
|---|---|---|
| `warranties` | `id`, `vehicle_id`, `warranty_type`, `start_date`, `end_date`, `status`, `correlation_id`, timestamps | PK `id`; unique `(vehicle_id,warranty_type)`; checks end date >= start date và status PENDING/ACTIVE/EXPIRED; `ix_warranties_coverage(vehicle_id,status,start_date,end_date)`; `ix_warranties_expiry(status,end_date)` |

`correlation_id` nullable thêm trong migration 0002, không có index. Coverage query hiện tại dùng danh sách warranty theo `vehicle_id`, sau đó lọc status/date trong Python; không thực hiện SQL predicate coverage trực tiếp.

### Ý nghĩa cột

| Cột | Ý nghĩa, nullability và quy tắc |
|---|---|
| `id UUID` | Khóa chính do ứng dụng sinh, không null. |
| `vehicle_id UUID` | ID xe từ `vehicle_db`; không null nhưng không có khóa ngoại xuyên database. |
| `warranty_type VARCHAR(50)` | Loại bảo hành, là một phần của unique key với `vehicle_id`. |
| `start_date DATE`, `end_date DATE` | Hai đầu khoảng ngày bảo hành; không null và CHECK `end_date >= start_date`. Coverage bao gồm cả ngày đầu và cuối. |
| `status VARCHAR(20)` | Mặc định PENDING; CHECK chỉ nhận PENDING, ACTIVE, EXPIRED. Default warranty được tạo ACTIVE bằng service logic. |
| `correlation_id VARCHAR(128)` | Cho phép NULL; được thêm để nối REST request với thay đổi WAL/CDC. |
| `created_at`, `updated_at TIMESTAMPTZ` | Không null; theo dõi thời điểm tạo/cập nhật row. |

Unique `(vehicle_id,warranty_type)` có hai tác dụng: bảo vệ invariant nghiệp vụ khi nhiều REST retry cùng lúc và tạo index tra cứu theo vehicle/type. Vì `vehicle_id` đứng đầu, index này có thể hỗ trợ lọc chỉ theo vehicle, nhưng query history hiện vẫn dùng index coverage khai báo riêng.

Source: [warranty model](../../services/warranty-service/app/models/warranty.py), [warranty migrations](../../services/warranty-service/migrations/versions/).

## 5. `inspection_db`

| Table | Cột nghiệp vụ chính | Keys, constraints và indexes |
|---|---|---|
| `vehicle_references` | `vehicle_id`, `vehicle_seen`, `warranty_seen`, `vehicle_payload JSONB`, `source_updated_at`, `warranty_id`, `workflow_status`, `prepared_at`, timestamps | PK `vehicle_id`; không FK tới domain DB khác |
| `vehicle_warranty_projection` | `warranty_id`, `vehicle_id`, `warranty_status/type`, dates, `source_updated_at`, `synced_at`, `source_lsn`, `source_partition`, `source_offset`, `is_deleted` | PK `warranty_id`; `ix_vehicle_warranty_projection_vehicle_id(vehicle_id)` |
| `inspections` | `id`, `vehicle_id`, `warranty_id`, `inspection_type`, `status`, `result`, `failure_reason`, `notes`, `completed_at`, timestamps | PK `id`; checks trạng thái, completion/result/date và failure reason; `ix_inspections_vehicle_created(vehicle_id,created_at)` |
| `inspection_reports` | `id`, `inspection_id`, `vehicle_id`, `kind`, `priority`, `status`, `task_id`, correlation/attempts/timestamps/error, report metadata, `document BYTEA` | PK `id`; FK `inspection_id → inspections.id`; unique `inspection_id`, unique `task_id`; checks status/kind/document consistency; `ix_inspection_reports_dispatch(priority,created_at) WHERE status='PENDING'`; `ix_inspection_reports_open(status) WHERE status<>'GENERATED'` |

`vehicle_references` được mở rộng trong migration 0002; projection table cũng được tạo tại revision này. `inspection_reports` được thêm ở 0003; document được deferred trong ORM để các query metadata không tự tải PDF. Các index inspection/report nằm trong [model](../../services/inspection-service/app/models/inspection.py) và [migrations](../../services/inspection-service/migrations/versions/).

### Ý nghĩa cột và giới hạn invariant

| Table | Cột | Ý nghĩa, nullability và quy tắc |
|---|---|---|
| `vehicle_references` | `vehicle_id UUID` | Khóa chính; ID logic từ Vehicle database, không có khóa ngoại xuyên database. |
| | `vehicle_seen`, `warranty_seen BOOLEAN` | Không null; đánh dấu đã nhận từng nguồn đầu vào. |
| | `vehicle_payload JSONB` | Cho phép NULL trước event xe; giữ snapshot payload để dùng cục bộ. |
| | `source_updated_at TIMESTAMPTZ` | Cho phép NULL; thời điểm nguồn dùng để bỏ qua event xe cũ. |
| | `warranty_id UUID` | Cho phép NULL khi chưa có warranty projection chưa xóa. |
| | `workflow_status VARCHAR(30)` | Không null, mặc định WAITING_VEHICLE; code tính WAITING_VEHICLE/WAITING_WARRANTY/READY. Migration chưa đặt CHECK cho tập giá trị. |
| | `prepared_at TIMESTAMPTZ` | Cho phép NULL; thời điểm row lần đầu đạt READY. |
| | timestamps | Ngày tạo/cập nhật projection cục bộ. |
| `vehicle_warranty_projection` | `warranty_id UUID` | Khóa chính; định danh row nguồn bảo hành. |
| | `vehicle_id UUID` | ID logic của xe; index riêng để tìm các warranty của xe. |
| | `warranty_status`, `warranty_type` | Giá trị được sao chép từ row Warranty; không có CHECK trong migration projection. |
| | `start_date`, `end_date DATE` | Khoảng ngày được giải mã từ CDC; không có CHECK cục bộ. |
| | `source_updated_at`, `synced_at TIMESTAMPTZ` | Thời gian nguồn cập nhật và thời gian Inspection áp dụng CDC. |
| | `source_lsn BIGINT`, `source_partition INTEGER`, `source_offset BIGINT` | Vị trí nguồn để bỏ qua CDC cũ hơn; không có index riêng. |
| | `is_deleted BOOLEAN` | Mặc định false; tombstone/delete đặt true nhưng giữ checkpoint để snapshot cũ không hồi sinh row. |
| `inspections` | `id UUID`, `vehicle_id UUID` | Khóa chính và logical reference tới xe; vehicle ID không có khóa ngoại. |
| | `warranty_id UUID` | Cho phép NULL; warranty ID được chọn lúc tạo inspection. Không tự đổi khi projection thay đổi. |
| | `inspection_type VARCHAR(50)` | Giá trị API hiện nhận DELIVERY/PERIODIC/DIAGNOSTIC; DB không có CHECK loại này. |
| | `status VARCHAR(20)` | Mặc định PENDING; CHECK PENDING/IN_PROGRESS/COMPLETED. |
| | `result VARCHAR(10)`, `failure_reason TEXT` | Cho phép NULL trước hoàn tất. CHECK yêu cầu FAIL có reason không rỗng và PASS không có reason. |
| | `notes TEXT` | Cho phép NULL; giới hạn độ dài được áp dụng ở API, không phải kiểu TEXT trong DB. |
| | `completed_at TIMESTAMPTZ` | Cho phép NULL trước hoàn tất; CHECK yêu cầu COMPLETED có result và thời điểm, trạng thái khác thì result/thời điểm phải NULL. |
| | timestamps | Thời điểm tạo/cập nhật inspection. |
| `inspection_reports` | `id UUID`, `inspection_id UUID`, `vehicle_id UUID` | Khóa chính; inspection ID có FK cùng database và unique để tối đa một report mỗi inspection; vehicle ID là logical reference. |
| | `kind VARCHAR(20)`, `priority SMALLINT` | CERTIFICATE hoặc DEFECT_REPORT; priority AMQP 0/9 theo service. Kind có CHECK; priority không có CHECK. |
| | `status VARCHAR(20)`, `task_id UUID` | Status bị giới hạn bởi CHECK; task ID unique và ổn định qua retry/re-delivery. |
| | `correlation_id VARCHAR(64)` | Cho phép NULL để liên kết report với request/event. |
| | `attempts`, `dispatch_attempts INTEGER` | Mặc định 0; tách số lần worker xử lý với số lần dispatcher gửi. |
| | `next_dispatch_at TIMESTAMPTZ` | Mặc định hiện tại; dispatcher chỉ chọn row đến hạn. |
| | `queued_at`, `started_at`, `generated_at`, `failed_at TIMESTAMPTZ` | Mốc vòng đời; cho phép NULL cho tới khi bước tương ứng xảy ra. |
| | `worker VARCHAR(255)`, `last_error TEXT` | Cho phép NULL; worker cuối xử lý và thông tin lỗi. |
| | `report_number VARCHAR(40)`, `sha256 VARCHAR(64)`, `size_bytes INTEGER` | Cho phép NULL trước khi sinh; metadata nhận diện tài liệu và kích thước. |
| | `document BYTEA` | Cho phép NULL trước khi sinh; chứa PDF. ORM trì hoãn tải cột này khi đọc metadata. |
| | timestamps | Thời điểm tạo và cập nhật yêu cầu báo cáo. |

CHECK của report yêu cầu biểu thức `(status='GENERATED')` phải bằng việc cả `document`, `sha256`, `generated_at` đều khác NULL. Đây không phải CHECK từng cột phải NULL trong mọi trạng thái khác GENERATED; service mới là nơi quản lý lifecycle còn lại.

## 6. `repair_db`

| Table | Cột nghiệp vụ chính | Keys, constraints và indexes |
|---|---|---|
| `repair_requests` | `id`, `vehicle_id`, `inspection_id`, `warranty_id`, `warranty_covered`, `status`, `description`, defect report number/hash/time, timestamps | PK `id`; unique `inspection_id`; status check; `ix_repairs_vehicle_created(vehicle_id,created_at)`; không FK sang Inspection/Warranty DB |
| `notifications` | `id`, `vehicle_id`, `repair_id`, `channel`, `message`, `status`, timestamps | PK `id`; FK `repair_id → repair_requests.id`; unique `(repair_id,channel)` |

`warranty_id` được thêm ở migration 0002; defect report metadata ở 0003. Unique `(repair_id,channel)` bắt đầu bằng `repair_id`, nên hỗ trợ lookup notifications theo repair. `repair_requests.inspection_id` unique hỗ trợ lookup/dedupe một repair trên mỗi inspection.

### Ý nghĩa cột

| Table | Cột | Ý nghĩa, nullability và quy tắc |
|---|---|---|
| `repair_requests` | `id UUID` | Khóa chính do ứng dụng sinh. |
| | `vehicle_id UUID`, `inspection_id UUID` | Logical references; inspection ID unique nhưng không FK xuyên database. |
| | `warranty_id UUID` | Cho phép NULL; ID warranty do Warranty API trả về lúc tạo. |
| | `warranty_covered BOOLEAN` | Không null; snapshot covered/uncovered lúc tạo. Khi Warranty không trả lời, transaction rollback chứ không ghi false. |
| | `status VARCHAR(20)` | Mặc định OPEN; CHECK OPEN/IN_PROGRESS/COMPLETED/CANCELLED. Transition hợp lệ được kiểm ở service. |
| | `description TEXT` | Không null; caller hoặc event inspection cung cấp. |
| | `defect_report_number VARCHAR(40)`, `defect_report_sha256 VARCHAR(64)`, `defect_report_generated_at TIMESTAMPTZ` | Cho phép NULL; được thêm bằng migration 0003 khi report FAIL được phát hành. Không có CHECK buộc ba giá trị cùng xuất hiện. |
| | timestamps | Thời điểm tạo/cập nhật repair. |
| `notifications` | `id UUID`, `vehicle_id UUID` | Khóa chính và logical reference tới xe. |
| | `repair_id UUID` | Không null; FK nội bộ tới `repair_requests.id`. |
| | `channel VARCHAR(20)`, `status VARCHAR(20)` | Mặc định LOG/SIMULATED trong ORM; DB không khai báo CHECK cho tập giá trị. |
| | `message TEXT` | Nội dung notification mô phỏng; không phải bằng chứng provider đã gửi email/SMS. |
| | timestamps | Thời điểm tạo/cập nhật notification. |

Unique `(repair_id,channel)` cho phép nhiều channel trên một repair về mặt schema, nhưng hiện service chỉ tạo một row LOG. Schema không bắt buộc repair phải có notification; đó là behavior của transaction service.

Source: [repair model](../../services/repair-service/app/models/repair.py), [repair migrations](../../services/repair-service/migrations/versions/).

## 7. Vì sao các chỉ mục này tồn tại

Chỉ mục (index) là cấu trúc phụ giúp PostgreSQL tìm row mà không quét cả bảng. Đổi lại, mỗi insert/update có thể phải cập nhật thêm index và index chiếm đĩa/bộ nhớ. Các index dưới đây là B-tree mặc định, trừ các index có điều kiện chỉ chứa một phần row. Khóa chính và ràng buộc unique tự sinh backing unique index.

| Index | Query path được hỗ trợ | Lưu ý hiện trạng |
|---|---|---|
| `vehicles_vin_key` | `vehicles.vin = :vin` | Exact-match/reconcile |
| `ix_vehicles_created(created_at,id)` | List vehicles order by created/id | Không bao gồm filter khác ngoài VIN |
| `ix_warranty_provision_requests_status(status)` | Đếm/chọn PENDING provision | Không bao gồm `next_attempt_at, created_at` |
| `uq_warranty_vehicle_type(vehicle_id,warranty_type)` | Dedupe theo vehicle/type | Unique business key |
| `ix_warranties_coverage(vehicle_id,status,start_date,end_date)` | Lấy candidate coverage theo vehicle | App hiện lấy history theo vehicle, lọc status/date trong Python |
| `ix_warranties_expiry(status,end_date)` | Warranty hết hạn theo status/date | Phù hợp filter worker expiry |
| `ix_inspections_vehicle_created(vehicle_id,created_at)` | Danh sách inspection theo vehicle/thời gian | ORDER BY còn `id`; planner có thể cần sort tie |
| `ix_vehicle_warranty_projection_vehicle_id(vehicle_id)` | Tìm warranty projection của một vehicle | Primary key riêng là warranty_id |
| `inspection_reports_inspection_id_key` | Report theo inspection ID | Unique |
| `inspection_reports_task_id_key` | Dedupe task ID | Unique |
| `ix_inspection_reports_dispatch(priority,created_at)` partial PENDING | Dispatcher claim | Query order priority DESC; planner có thể cần sort |
| `ix_inspection_reports_open(status)` partial not GENERATED | Metrics/open report rows | Giảm phạm vi so với index toàn bảng |
| `repair_requests_inspection_id_key` | Repair theo inspection ID | Unique |
| `ix_repairs_vehicle_created(vehicle_id,created_at)` | Danh sách repair theo vehicle/time | API cũng có thể filter inspection ID; index không ghép hai filter |
| `uq_notification_repair_channel(repair_id,channel)` | Notification theo repair và uniqueness theo channel | Prefix hỗ trợ lookup chỉ theo repair |
| `ix_outbox_pending(next_attempt_at,id)` partial PENDING | Tìm event đến hạn | Dùng chung với aggregate-order predicate |
| `ix_outbox_aggregate(aggregate_id,id)` partial PENDING | Kiểm event cũ hơn cùng aggregate | Giữ thứ tự publish aggregate |
| `processed_events` PK `(event_id,consumer_name)` | Claim/lookup event cho consumer | Không có secondary index |
| `idempotency_records` PK và UNIQUE `(scope,key_hash)` | Reserve/replay API key | DDL hiện tạo hai uniqueness structures cho cùng cặp; đánh giá migration riêng trước khi thay |

Index không được khai báo: không có index riêng cho `notifications.vehicle_id`, các cột vị trí nguồn CDC, `repair_requests.created_at` độc lập, `inspections.created_at` độc lập hoặc `warranties.correlation_id`. Các trường hợp quan trọng cần hiểu:

- Query list theo `vehicle_id` và order `(created_at,id)` có index bắt đầu bằng vehicle/time nhưng thiếu `id`; nếu nhiều row cùng timestamp PostgreSQL có thể sort thêm hoặc dùng kế hoạch khác.
- List inspection/repair không lọc theo vehicle không có index phù hợp trực tiếp với `created_at`; PostgreSQL có thể chọn sequential scan rồi sort. Giới hạn page nhỏ không loại bỏ chi phí nếu bảng đã lớn.
- Dispatcher warranty provision lọc trạng thái và thời điểm đến hạn, sau đó chọn row cũ nhất. Index chỉ trên `status` giảm candidate theo trạng thái nhưng vẫn có thể cần lọc due-time và sort. Đây là điểm cần đo nếu backlog lớn, không tự động đồng nghĩa phải thêm index.
- Index report dispatcher bắt đầu bằng priority nhưng truy vấn sort priority giảm dần; PostgreSQL có thể scan ngược hoặc sort tùy predicate/kế hoạch. Xác nhận bằng `EXPLAIN` thay vì suy luận từ tên index.
- Projection lookup lọc `vehicle_id` và `is_deleted=false`, rồi sort loại/ID. Chỉ có index vehicle; filter deleted và sort có thể tốn thêm khi một xe có nhiều warranty rows.
- Bảng ledger tăng theo thời gian và không có cleanup hiện tại. Index giúp tra cứu nhưng không giải quyết tăng kích thước; retention phải bảo đảm không xóa marker còn cần cho retry/replay.

Các nhận xét trên là phân tích cấu trúc, chưa phải benchmark. Cần dùng thống kê planner cập nhật và dữ liệu đại diện để đánh giá thực tế.

## 8. Kiểm tra schema runtime

```sh
docker compose exec vehicle-service alembic current
docker compose exec warranty-service alembic current
docker compose exec inspection-service alembic current
docker compose exec repair-service alembic current
docker compose exec vehicle-service alembic check
docker compose exec postgres-primary psql -U platform_admin -d vehicle_db -c '\dt+'
docker compose exec postgres-primary psql -U platform_admin -d vehicle_db -c '\di+'
```

`alembic check` so sánh metadata của lớp ánh xạ Python với migration state; `\di+` hoặc catalog query cho biết index thực tế trong volume đang chạy. DDL CDC được bootstrap ngoài Alembic nên cần kiểm tra riêng `cdc_heartbeat` và publication. Bảng dưới đây mô tả schema source; dữ liệu volume cũ có thể cần migration mới để khớp.