# Danh mục truy vấn cơ sở dữ liệu

Danh mục này mô tả truy vấn PostgreSQL được dùng từ API, worker nền, consumer và bộ thu thập số liệu. Phần lớn truy vấn được viết bằng SQLAlchemy chứ không phải chuỗi SQL. Các mẫu SQL bên dưới diễn đạt cùng logic nhưng không đảm bảo giống từng ký tự trong log PostgreSQL. Cột “mục đích” cho biết vì sao query tồn tại; phần phân tích nêu khóa, transaction và hệ quả khi dữ liệu tăng.

## Cách đọc thuật ngữ

- `SELECT`: đọc dữ liệu; `INSERT`: thêm row; `UPDATE`: sửa row; `DELETE`: xóa row.
- `WHERE`: điều kiện lọc; `ORDER BY`: thứ tự kết quả; `LIMIT/OFFSET`: số row tối đa và số row bỏ qua.
- `FOR UPDATE`: khóa row đã đọc cho tới khi transaction kết thúc; transaction khác muốn sửa row đó phải chờ.
- `SKIP LOCKED`: bỏ qua row đã bị worker khác khóa, hữu ích khi nhiều worker cùng lấy việc từ một bảng.
- `ON CONFLICT`: xử lý va chạm khóa unique ngay tại database, thay vì dựa vào thao tác “kiểm tra trước rồi chèn” vốn có race condition.
- `UPSERT`: thêm row; nếu trùng khóa thì cập nhật row hiện có. Trong PostgreSQL thường được viết `INSERT ... ON CONFLICT DO UPDATE`.
- `ACK`: xác nhận broker đã nhận message; ACK không tự commit transaction PostgreSQL.
- `PK` là khóa chính; `FK` là khóa ngoại. `:name` biểu diễn bind parameter do driver truyền tách khỏi SQL, không phải nối chuỗi.

Chỉ các câu `text()` trong mã ứng dụng và câu SQL trong migration là SQL viết trực tiếp. Câu SQLAlchemy được trình bày dưới dạng tương đương; tên cột có thể được SELECT đầy đủ hoặc một phần tùy ORM.

## 1. Kiểm tra kết nối, migration và replica

| Mục đích | Query tương đương | Code |
|---|---|---|
| Kiểm tra database còn nhận truy vấn | `SELECT 1` | [api.py](../../common/platform_common/api.py) |
| Read-only replica transaction | `SET TRANSACTION READ ONLY` | [runtime.py](../../common/platform_common/runtime.py) |
| Serialize migrations trong cùng DB | `SELECT pg_advisory_lock(72143819)` / `SELECT pg_advisory_unlock(72143819)` | `services/<service>/migrations/env.py` |
| Serialize projection updates theo vehicle | `SELECT pg_advisory_xact_lock(hashtextextended(:vehicle_id, 0))` | [inspection handlers](../../services/inspection-service/app/messaging/handlers.py) |

`SELECT 1` chỉ kiểm tra server chấp nhận truy vấn; không chứng minh consumer đang tiến triển hoặc Warranty API sẵn sàng. Advisory lock migration được lấy trước khi nâng schema và thả sau đó, tránh hai process cùng áp dụng một revision. Advisory transaction lock cho projection tự được thả khi transaction kết thúc, kể cả rollback.

Các pool đặt giới hạn thời gian câu lệnh và transaction nhàn rỗi; xem [Tổng quan hệ thống](SYSTEM_OVERVIEW.md#2-kết-nối-và-giao-dịch). Đọc replica dùng `SET TRANSACTION READ ONLY`; nếu truy vấn thành công nhưng trả rỗng thì ứng dụng không fallback, vì một kết quả rỗng hợp lệ có thể do độ trễ sao chép.

## 2. Vehicle Service

| Use case | Query shape hiện có | Behavior/index |
|---|---|---|
| Get vehicle | `SELECT ... FROM vehicles WHERE id=:id` | Có thể thêm `FOR UPDATE` cho mutation; PK lookup |
| List page | `SELECT ... FROM vehicles [WHERE vin=:vin] ORDER BY created_at,id LIMIT :limit OFFSET :offset` | Filter VIN dùng unique index; ordering dùng `ix_vehicles_created` |
| Create/update/delete | ORM `INSERT`; `SELECT ... FOR UPDATE` rồi `UPDATE`; ORM `DELETE` | Create cùng transaction với outbox + provision request; delete chỉ dữ liệu simulation marker hợp lệ |
| Find pending provision | `SELECT ... WHERE status='PENDING' AND next_attempt_at<=:now [AND vehicle_id=:id] ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED` | Worker claim một lệnh; tùy chọn retry theo vehicle sau create |
| Pending provision metric | `SELECT count(*) FROM warranty_provision_requests WHERE status='PENDING'` | Đếm queue durable; status index hiện có |

Code: [vehicle repository](../../services/vehicle-service/app/repositories/vehicles.py), [vehicle service](../../services/vehicle-service/app/services/vehicles.py), [provision worker](../../services/vehicle-service/app/services/warranty_provision.py).

### Phân tích

- GET theo ID sử dụng khóa chính. Với update/delete, `FOR UPDATE` nối query đọc với mutation để hai request đồng thời không ghi dựa trên cùng một trạng thái cũ.
- List có thứ tự ổn định nhờ thêm ID sau timestamp. Với `vin` exact-match, unique constraint vừa bảo vệ dữ liệu vừa làm đường tra cứu hiệu quả. Pagination bằng OFFSET có thể đắt ở offset lớn vì PostgreSQL vẫn phải tìm/bỏ qua row trước trang.
- Worker provision gọi `SKIP LOCKED` để nhiều bản sao không claim cùng lệnh. Row lock được giữ qua cuộc gọi HTTP tới Warranty trong code hiện tại; điều này ngăn worker trùng nhưng kéo dài transaction/kết nối theo latency mạng. Đây là trade-off đáng đo khi service Warranty chậm.
- Index status đơn không bao phủ cả lọc `next_attempt_at` và sắp `created_at`. Nếu backlog tăng, kiểm tra số rows được lọc và query plan trước khi thay index.

## 3. Warranty Service

| Use case | Query shape hiện có | Behavior/index |
|---|---|---|
| Get/transition warranty | `SELECT ... FROM warranties WHERE id=:id FOR UPDATE` | Khóa row trước khi transition |
| History/list/coverage candidate | `SELECT ... FROM warranties WHERE vehicle_id=:id ORDER BY created_at` | Coverage filter chạy trong Python theo status/date; index candidate có prefix vehicle_id |
| Create default | `INSERT ... ON CONFLICT (vehicle_id,warranty_type) DO NOTHING RETURNING ...`; nếu conflict thì `SELECT` lại theo vehicle/type | Chống REST retry duplicate, enqueue created chỉ khi insert mới |
| Expire due | `SELECT ... WHERE status IN ('ACTIVE','PENDING') AND end_date < :today LIMIT 100 FOR UPDATE SKIP LOCKED` | Chuyển EXPIRED và enqueue event trong cùng transaction |

Code: [warranty repository](../../services/warranty-service/app/repositories/warranties.py), [warranty service](../../services/warranty-service/app/services/warranties.py).

### Phân tích

- Coverage truy vấn history chứ không chạy predicate status/ngày trong SQL. Số row hiện nhỏ theo quy tắc một row mỗi loại bảo hành, nhưng nếu mô hình mở rộng nhiều policy/version thì tải toàn bộ history cho mỗi Repair sẽ tăng theo số row/xe.
- Thứ tự `created_at` khiến chọn row active đầu tiên xác định được khi có nhiều warranty cùng cover; unique chỉ giới hạn mỗi loại, không giới hạn tổng số loại.
- Worker expiry khóa tối đa 100 row và bỏ qua các row worker khác đã khóa. Nhiều chu kỳ xử lý backlog mà không cần một transaction cập nhật toàn bộ bảng; index `(status,end_date)` phục vụ lọc trạng thái/ngày.
- `LIMIT 100` không có `ORDER BY`; khi backlog vượt 100, thứ tự xử lý không được bảo đảm. Kết quả nghiệp vụ không phụ thuộc thứ tự, nhưng latency tới từng row có thể thay đổi.

## 4. Inspection Service và CDC projection

| Use case | Query shape hiện có | Behavior/index |
|---|---|---|
| Check workflow readiness | `SELECT ... FROM vehicle_references WHERE vehicle_id=:id` | PK lookup; cần `vehicle_seen` và `workflow_status='READY'` |
| List inspections | `SELECT ... FROM inspections [WHERE vehicle_id=:id] ORDER BY created_at,id LIMIT :limit OFFSET :offset` | Theo xe dùng composite index, sau đó có thể sort theo id khi timestamps bằng nhau |
| Mutate/complete inspection | `SELECT ... FROM inspections WHERE id=:id FOR UPDATE` | Completion immutable; report request + event outbox insert cùng transaction |
| Select projection candidate | `SELECT ... FROM vehicle_warranty_projection WHERE vehicle_id=:id AND is_deleted=false ORDER BY warranty_type,warranty_id LIMIT 1` | Không kiểm tra active/date; chỉ tạo readiness projection |
| Upsert vehicle event | `INSERT ... ON CONFLICT(vehicle_id) DO UPDATE ... WHERE source_updated_at IS NULL OR source_updated_at <= :event_time` | Bỏ qua domain event cũ |
| Upsert warranty CDC | `INSERT ... ON CONFLICT(warranty_id) DO UPDATE ... WHERE source_lsn < :lsn OR (source_lsn=:lsn AND (partition,offset) < (:partition,:offset))` | Giữ checkpoint mới hơn; delete lưu `is_deleted=true` |

Code: [inspection repository](../../services/inspection-service/app/repositories/inspections.py), [CDC handlers](../../services/inspection-service/app/messaging/handlers.py), [inspection service](../../services/inspection-service/app/services/inspections.py).

### Phân tích

- Readiness lookup theo khóa chính `vehicle_id`; không truy vấn Vehicle hoặc Warranty database. Vì vậy khả năng tạo inspection phụ thuộc độ tươi của event/CDC projection.
- Advisory lock theo vehicle ID được lấy trước thao tác projection vì row `vehicle_references` có thể chưa tồn tại. Khóa row thông thường không thể khóa một row chưa được insert; khóa advisory tạo điểm tuần tự hóa cho cả hai đường vehicle-event và CDC.
- CDC upsert so sánh LSN (vị trí trong WAL), rồi partition/offset để phân giải các record có cùng LSN. Điều này bảo vệ thứ tự xử lý tại consumer và replay snapshot cũ; nó không biến hai topic vehicle và warranty thành một thứ tự toàn cục.
- Query chọn warranty projection chỉ kiểm tra `is_deleted=false`, không kiểm tra trạng thái ACTIVE hoặc thời hạn. Đây là lựa chọn dữ liệu projection/readiness, không phải query coverage.
- List theo vehicle có thể tận dụng index `(vehicle_id,created_at)`. List toàn cục không có index tương ứng; thêm index toàn cục làm tăng chi phí mọi insert nên cần căn cứ workload.

## 5. API idempotency và Kafka consumer

| Use case | Query shape hiện có | Behavior |
|---|---|---|
| Reserve request key | `INSERT INTO idempotency_records (...) VALUES (...) ON CONFLICT (scope,key_hash) DO NOTHING RETURNING key_hash` | Unique reservation serialize concurrent requests |
| Store response | `UPDATE idempotency_records SET response=:json WHERE scope=:scope AND key_hash=:hash` | Cùng transaction với action/resource/outbox |
| Replay existing key | `SELECT ... FROM idempotency_records WHERE scope=:scope AND key_hash=:hash` | So sánh request hash; mismatch trả 409 |
| Claim event | `INSERT INTO processed_events(event_id,consumer_name) VALUES (...) ON CONFLICT DO NOTHING RETURNING event_id` | Marker cùng transaction với handler; conflict là duplicate |

Code: [idempotency.py](../../common/platform_common/idempotency.py), [consumer.py](../../common/platform_common/consumer.py).

### Phân tích

- Reservation được chèn trước business action trong cùng transaction. Nếu transaction A đang giữ unique key, transaction B cùng key sẽ đợi kết quả A: sau commit, B đọc response; sau rollback, một transaction có thể giành quyền xử lý.
- Request fingerprint tách payload khác nhau khỏi cùng idempotency key. Cache Redis có thể trả fast path, nhưng PostgreSQL ledger xử lý trường hợp Redis mất dữ liệu hoặc không truy cập được.
- Consumer insert marker trước handler để unique constraint quyết định duy nhất một transaction xử lý event. Marker và side effect phải cùng database transaction; side effect ngoài database (email, HTTP mutation khác) không được bảo vệ tự động.
- Kafka offset được commit sau transaction database. Điều này cho phép replay sau crash, đổi lại giao nhận có thể lặp và cần marker bền vững.

## 6. Publisher của bảng outbox

Query dưới đây chọn một event đến hạn, với điều kiện không có event PENDING cũ hơn của cùng aggregate. “Aggregate” là đối tượng nghiệp vụ dùng làm khóa thứ tự; trong luồng hiện tại thường là vehicle ID.

```sql
SELECT candidate.*
FROM outbox_events AS candidate
WHERE candidate.status = 'PENDING'
  AND candidate.next_attempt_at <= :now
  AND NOT EXISTS (
    SELECT older.id
    FROM outbox_events AS older
    WHERE older.aggregate_id = candidate.aggregate_id
      AND older.status = 'PENDING'
      AND older.id < candidate.id
  )
ORDER BY candidate.id
LIMIT 1
FOR UPDATE SKIP LOCKED;
```

Sau publish ACK, update cùng row thành PUBLISHED, `published_at=:now`, clear `last_error`. Khi publish lỗi, tăng attempts, lưu error và dời `next_attempt_at`. Transaction giữ row lock trong thời gian publish để claim không bị trùng; crash sau ACK nhưng trước commit có thể publish lại cùng event ID.

Code: [outbox.py](../../common/platform_common/outbox.py), enqueue: [events.py](../../common/platform_common/events.py).

### Phân tích

- `NOT EXISTS` tạo hàng rào head-of-line: event mới của cùng xe không vượt qua event cũ chưa publish. Các xe khác vẫn có thể tiến triển vì worker claim bằng `SKIP LOCKED`.
- Partial index PENDING giảm phạm vi index so với index toàn bảng; sau khi row chuyển PUBLISHED, nó không còn nằm trong index này.
- Publisher giữ khóa row trong lúc chờ Kafka. Ưu điểm là không cần lease table để claim; nhược điểm là transaction và kết nối PostgreSQL bị giữ trong suốt thời gian mạng chờ ACK.
- Nếu Kafka đã nhận event nhưng DB chưa commit PUBLISHED, lần sau publisher gửi lại cùng event ID. Đây là duplicate có chủ ý trong mô hình at-least-once.

## 7. Report dispatcher/worker

| Use case | Query shape hiện có | Behavior/index |
|---|---|---|
| Claim report tasks | `SELECT ... FROM inspection_reports WHERE status='PENDING' AND next_dispatch_at<=:now ORDER BY priority DESC,created_at LIMIT :batch FOR UPDATE SKIP LOCKED` | Publisher confirm rồi set QUEUED; lỗi giữ PENDING và backoff |
| Lock report by inspection | `SELECT ... FROM inspection_reports WHERE inspection_id=:id FOR UPDATE` | Worker kiểm GENERATED/claim PROCESSING/commit document |
| Read inspection/report metadata | `SELECT ... FROM inspection_reports WHERE inspection_id=:id` | Unique inspection ID |
| Read PDF body | Same lookup plus deferred `document` column explicitly undeferred | Không tải BYTEA khi chỉ lấy metadata |
| Report status metrics | `SELECT status,count(*) FROM inspection_reports WHERE status<>'GENERATED' GROUP BY status` | Poll mỗi 5 giây; generated rows không được scan cho gauge |

Worker cũng lấy Inspection, VehicleReference và VehicleWarrantyProjection bằng PK (`session.get`). Code: [dispatcher.py](../../services/inspection-service/app/reports/dispatcher.py), [tasks.py](../../services/inspection-service/app/reports/tasks.py), [inspection service](../../services/inspection-service/app/services/inspections.py).

### Phân tích

- `SKIP LOCKED` cho phép nhiều dispatcher xử lý các report row khác nhau. Sắp priority giảm dần khiến report lỗi được lấy trước certificate PASS, sau đó dùng thời gian tạo để ưu tiên row cũ hơn trong cùng mức priority.
- Dispatcher thực hiện publish broker trong transaction đang giữ row locks. Batch lớn tăng throughput publish nhưng cũng kéo dài số lock/kết nối; `report_dispatch_batch` nên được đánh giá cùng timeout broker và pool size.
- Worker không giữ transaction mở trong lúc render PDF. Nó dùng một transaction claim ngắn, render ngoài DB, rồi mở transaction commit. Nếu worker chết giữa render và commit, broker có thể giao lại task; render lại được phép, nhưng khóa và trạng thái GENERATED chặn lưu kết quả lần hai.
- Cột PDF BYTEA bị deferred để truy vấn report metadata không đọc cả blob. Endpoint tải PDF chủ động yêu cầu cột này và chỉ trả khi status GENERATED.
- Gauge report đếm mọi status khác GENERATED, group theo status. Row GENERATED không bị quét cho metric vì số row hoàn tất tăng mãi.

## 8. Repair Service

| Use case | Query shape hiện có | Behavior/index |
|---|---|---|
| Get/update repair | `SELECT ... FROM repair_requests WHERE id=:id [FOR UPDATE]` | PK lookup; transition được kiểm trong service |
| Find duplicate by inspection | `SELECT ... FROM repair_requests WHERE inspection_id=:id` | Unique index, dùng trước và sau insert conflict |
| List repairs | `SELECT ... [WHERE vehicle_id=:v] [AND inspection_id=:i] ORDER BY created_at,id LIMIT :limit OFFSET :offset` | Index vehicle/time hoặc unique inspection; filter kết hợp không có composite riêng |
| List notifications | `SELECT ... FROM notifications WHERE repair_id=:id` | Unique `(repair_id,channel)` có prefix phù hợp |
| Create new repair | `INSERT ... ON CONFLICT(inspection_id) DO NOTHING RETURNING ...` | Coverage REST được gọi trước insert; repair + notification + outbox cùng transaction |
| Attach generated report | `SELECT ... FROM repair_requests WHERE inspection_id=:id FOR UPDATE`, sau đó ORM `UPDATE repair_requests ... WHERE id=:repair_id` khi flush | Thực hiện trong consumer handler transaction; PASS không truy vấn repair |

Code: [repair repository](../../services/repair-service/app/repositories/repairs.py), [repair service](../../services/repair-service/app/services/repairs.py), [handler](../../services/repair-service/app/messaging/handlers.py).

### Phân tích

- Unique inspection ID là đồng bộ hóa nghiệp vụ cuối cùng giữa API và Kafka consumer. Kiểm tra trước insert giúp tránh gọi Warranty cho repair đã có; `ON CONFLICT` vẫn cần thiết vì hai tiến trình có thể cùng qua bước kiểm tra trước khi một bên insert.
- API list chỉ có index theo vehicle/time; khi lọc đồng thời vehicle và inspection, index hiện có không khớp hoàn toàn, nhưng inspection ID unique có thể là đường truy cập tốt hơn tùy planner và predicate.
- Truy vấn notification theo repair dùng prefix của unique index `(repair_id,channel)`. Không có index riêng cho `vehicle_id` trên notifications vì code hiện truy vấn theo repair.

## 9. Các query kiểm tra vận hành

Runbook hiện có các truy vấn SQL do operator chạy trực tiếp. Chúng không phải truy vấn được API phát tự động:

```sql
SELECT event_id, event_type, status, attempts, now()-created_at AS age,
       next_attempt_at, last_error
FROM outbox_events
WHERE status = 'PENDING'
ORDER BY id
LIMIT 20;

SELECT event_id, consumer_name, processed_at
FROM processed_events
ORDER BY processed_at DESC
LIMIT 20;

SELECT id, vehicle_id, inspection_id, warranty_covered, status
FROM repair_requests
ORDER BY created_at DESC
LIMIT 20;

SELECT status, count(*)
FROM warranties
GROUP BY status;
```

Lệnh nguồn và các truy vấn DB/Kafka khác nằm trong [Operations](../OPERATIONS.md) và [Data Model](../DATA_MODEL.md#7-migrations-query-và-retention). Các câu này là chẩn đoán operator, không phải request path của API.

## 10. Điều cần xác minh trước khi tối ưu

- Warranty coverage hiện tải toàn bộ warranty history của vehicle rồi lọc trong Python; nếu lịch sử tăng đáng kể, đo và cân nhắc đẩy predicate status/date xuống DB.
- Inspection projection lấy một warranty chưa deleted, không lọc `warranty_status` hoặc khoảng ngày. Không tái dùng query này để quyết định coverage.
- List inspections/repairs có thể sort `id` ngoài index sau khi sort timestamp; list toàn cục không có index chuyên cho `created_at`.
- Provision dispatcher filter status + due time, order created_at nhưng chỉ có index status.
- `idempotency_records` migration có UNIQUE lặp composite PK; kiểm tra index runtime trước khi quyết định migration dọn.
- Đây là nhận xét từ cấu trúc query và schema, không phải kết luận về latency. Dùng `EXPLAIN (ANALYZE, BUFFERS)` trên database thử nghiệm có lượng và phân bố dữ liệu tương tự; `ANALYZE` thực thi query nên không dùng tùy tiện trên câu ghi.
- Đọc `rows` ước lượng so với thực tế, số buffer đọc, loại scan, sort và số row bị loại bởi filter. Trước khi thêm index, xác nhận planner có thống kê cập nhật và query thực sự nằm trên đường nóng.
- Index làm tăng dung lượng, write amplification và chi phí vacuum/reindex; index dư thừa giữa primary key và unique constraint đặc biệt cần xác minh bằng `pg_indexes` trước khi tạo migration dọn.
- Khi thay query coverage hoặc index projection, chạy test kiểm tra ngày biên, warranty EXPIRED, CDC delete/replay và event đến sai thứ tự; tốc độ nhanh nhưng đổi semantics là regression.