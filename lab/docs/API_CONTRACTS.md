# REST API Contracts

[Mục lục](README.md) · [State machines](DATA_MODEL.md) · [Curl chạy đầy đủ](../README.md#26-api-examples)

## 1. Quy ước chung

| Service | Base URL mặc định | OpenAPI sống |
|---|---|---|
| Vehicle | `http://localhost:8001` | [Swagger](http://localhost:8001/docs) / [JSON](http://localhost:8001/openapi.json) |
| Warranty | `http://localhost:8002` | [Swagger](http://localhost:8002/docs) / [JSON](http://localhost:8002/openapi.json) |
| Inspection | `http://localhost:8003` | [Swagger](http://localhost:8003/docs) / [JSON](http://localhost:8003/openapi.json) |
| Repair | Cổng cấp động trong 8004–8006 | Thêm `/docs` hoặc `/openapi.json` vào URL thực tế |

Lấy Repair base URL bằng `REPAIR_URL="http://$(docker compose port --index 1 repair-service 8000)"`. Cổng có thể đổi khi recreate/scale container; chạy lại lệnh trước khi dùng curl.

Request/response JSON, UUID cho IDs và ISO 8601 cho thời gian. Request schemas cấm extra fields. Chưa có URL version prefix hoặc authentication. Trong network Compose dùng tên service với port 8000, không dùng host port.

Headers `X-Request-ID`, `X-Correlation-ID` nhận UUID hợp lệ; không có hoặc sai định dạng thì middleware sinh UUID mới. Response đi qua middleware bình thường trả lại cả hai. Đây là correlation thủ công, chưa có W3C trace context/OpenTelemetry.

List vehicle/inspection/repair trả **JSON array**, không có wrapper `items/total`. `limit=20` mặc định, 1–100; `offset=0` mặc định, không âm. GET warranty list theo xe trả array tất cả warranty của xe, không phân trang.

Vehicle detail GET hỗ trợ `?consistency=eventual`: đọc replica, bỏ qua cache; replica lỗi thì fallback primary. Headers `X-Read-Source: replica|primary-fallback`, `X-Cache: BYPASS`. Replica lag có thể trả 404 dù primary vừa commit; 404 này không kích hoạt fallback. Mặc định đọc cache/primary như trước, trả `X-Read-Source: cache|primary`. Xem [read routing](POSTGRESQL_CDC.md#4-read--write-routing-và-consistency).

## 2. Vehicle endpoints

| Method | Path | Input | Thành công | Lỗi đáng chú ý |
|---|---|---|---|---|
| POST | `/vehicles` | VehicleCreate | 201 VehicleRead | 409 VIN trùng |
| GET | `/vehicles` | limit, offset, vin exact-match tùy chọn | 200 array VehicleRead | 422 query sai |
| GET | `/vehicles/{vehicle_id}` | UUID | 200 VehicleRead; X-Cache HIT/MISS | 404 vehicle_not_found |
| PATCH | `/vehicles/{vehicle_id}` | VehicleUpdate | 200 VehicleRead | 404; 422 empty/null patch |
| DELETE | `/vehicles/{vehicle_id}` | X-Simulation-Run-ID UUID bắt buộc | 204 empty | 403 simulation_delete_forbidden; 404 vehicle_not_found; 422 header sai/thiếu |

VehicleCreate:

```json
{
  "vin": "LAB0123456789ABCD",
  "model": "EV-Lab",
  "manufacturer": "Learning Motors",
  "production_year": 2026,
  "owner_name": "Nguyen Van An"
}
```

VIN phải đủ 17 ký tự, gồm chữ hoa hoặc chữ số, loại trừ I/O/Q theo pattern `^[A-HJ-NPR-Z0-9]{17}$`. Ví dụ trên có LAB + 14 ký tự. Các lệnh chạy thực tế trong README sinh VIN mới tự động. `model/manufacturer`: 1–100; `owner_name`: 1–200; year: 1886–2100. POST không nhận `id`, `status` hay timestamp.

VehicleRead có các field của create và `id`, `status`, `created_at`, `updated_at`. Default status ACTIVE. PATCH chỉ nhận model, manufacturer, production_year, owner_name, status ACTIVE/INACTIVE; ít nhất một field và không field nào được null. VIN không sửa được.

`simulation_run_id` là UUID nullable tùy chọn trong VehicleCreate/Read, mặc định null. Có marker thì VIN phải bắt đầu `TRF`; marker bất biến qua PATCH. GET list với `vin` dùng unique VIN trên primary, phục vụ reconcile POST timeout; không đọc cache/replica. DELETE khóa row và chỉ cho phép VIN `TRF` có persisted marker bằng header, rồi invalidate cache. Header không phải cơ chế xác thực trong lab chưa auth. Không có bulk DELETE hay cascade xuống warranty/inspection/repair; không phát vehicle.deleted. DELETE lần nữa trả 404. Xem [phạm vi dữ liệu mô phỏng](TRAFFIC_GENERATOR.md#6-insert--update--delete-qua-rest).

Create/update enqueue vehicle.created/updated trong cùng transaction. GET dùng cache; `X-Cache=MISS` bao gồm cả Redis unavailable, không đồng nghĩa Redis chắc chắn hoạt động.

## 3. Warranty endpoints

| Method | Path | Input | Thành công | Lỗi đáng chú ý |
|---|---|---|---|---|
| POST | `/warranties` | WarrantyCreate | 201 WarrantyRead | 409 vehicle_not_ready hoặc unique conflict |
| GET | `/warranties/vehicle/{vehicle_id}` | UUID | 200 array; có thể `[]` | UUID sai → 422 |
| GET | `/warranties/vehicle/{vehicle_id}/active` | UUID | 200 Coverage | 404 warranty_not_ready |
| POST | `/warranties/{warranty_id}/activate` | Không cần body | 200 WarrantyRead | 404; 409 invalid_transition |
| POST | `/warranties/{warranty_id}/expire` | Không cần body | 200 WarrantyRead | 404 |

WarrantyCreate gồm `vehicle_id`, `warranty_type` EXTENDED/POWERTRAIN (default EXTENDED), `start_date`, `end_date`. End date không trước start date. DEFAULT tạo bằng `POST /internal/warranties` từ A; body gồm vehicle_id và vehicle_created_at. Natural key vehicle/type dedupe REST retries. Manual create cần xe đã có warranty history; không gọi Vehicle REST để xác minh.

WarrantyRead: `id`, `vehicle_id`, `warranty_type`, `start_date`, `end_date`, `status`, `created_at`, `updated_at`.

Coverage response:

```json
{
  "vehicle_id": "02fc3c76-9c9a-483c-bdc3-62b2be3608f0",
  "covered": true,
  "warranty_id": "153c7323-d3e9-48e0-985d-087c114b78bb",
  "checked_at": "2026-09-30T10:00:00Z"
}
```

`covered=false` đi với `warranty_id=null` khi đã có history nhưng không có warranty active theo ngày. 404 có thể là xe chưa tồn tại hoặc REST provision chưa được xử lý; endpoint chưa phân biệt hai trường hợp. Khi nhiều warranty active, implementation chọn record hợp lệ đầu tiên theo thứ tự created_at; repair giữ boolean coverage và nullable warranty_id.

Activate/expire gọi lại cùng trạng thái thành công, không phát lại event. Activate EXPIRED hoặc PENDING ngoài khoảng ngày trả 409. Expire thủ công cho phép kết thúc trước hạn.

## 4. Inspection endpoints

| Method | Path | Input | Thành công | Lỗi đáng chú ý |
|---|---|---|---|---|
| POST | `/inspections` | InspectionCreate + Idempotency-Key | 201 InspectionRead | 409 projection chưa sẵn sàng/key conflict; 422 thiếu key |
| GET | `/inspections` | vehicle_id tùy chọn, limit, offset | 200 array | 422 |
| GET | `/inspections/{inspection_id}` | UUID | 200 InspectionRead | 404 inspection_not_found |
| PATCH | `/inspections/{inspection_id}` | notes/status | 200 InspectionRead | 409 inspection_completed |
| POST | `/inspections/{inspection_id}/complete` | result/reason/notes | 200 InspectionRead | 409 completion_conflict; 422 result/reason sai |

InspectionCreate gồm `vehicle_id`, `inspection_type` DELIVERY/PERIODIC/DIAGNOSTIC (default PERIODIC), `notes` nullable tối đa 4000 ký tự. Header Idempotency-Key dài 1–128. Response fields: id, vehicle_id, warranty_id, inspection_type, status, result, failure_reason, notes, created_at, updated_at, completed_at.

PATCH nhận `status="IN_PROGRESS"` và/hoặc notes; `notes=null` để xóa ghi chú. Không nhận status=null hoặc empty patch. Completed inspection không sửa được qua PATCH, kể cả notes.

Complete FAIL:

```json
{
  "result": "FAIL",
  "failure_reason": "High voltage battery coolant leak",
  "notes": "Requires replacement"
}
```

Complete PASS: `{"result":"PASS"}`. FAIL bắt buộc reason không rỗng; PASS không được kèm reason khác null. Nếu không gửi notes khi complete, giữ notes cũ; gửi null sẽ xóa notes. Completed result/reason khác lần đầu, hoặc notes được gửi khác giá trị đã lưu, trả 409. Complete giống lần đầu không phát event trùng.

201 tạo inspection **không** phát inspection.created. Event chỉ phát khi complete PASS/FAIL.

## 5. Repair endpoints

| Method | Path | Input | Thành công | Lỗi đáng chú ý |
|---|---|---|---|---|
| POST | `/repairs` | RepairCreate + Idempotency-Key | 201 RepairRead | 503 warranty/lock; 409 key/vehicle conflict |
| GET | `/repairs` | vehicle_id, inspection_id tùy chọn; limit, offset | 200 array | 422 |
| GET | `/repairs/{repair_id}` | UUID | 200 RepairRead | 404 repair_not_found |
| PATCH | `/repairs/{repair_id}` | status | 200 RepairRead | 409 invalid_transition |
| GET | `/repairs/{repair_id}/notifications` | UUID | 200 array NotificationRead | 404 nếu repair không tồn tại |

RepairCreate: `vehicle_id`, `inspection_id`, `description` 1–4000 ký tự sau trim. RepairRead thêm `id`, `warranty_id` nullable, `warranty_covered`, `status`, `created_at`, `updated_at`. POST cùng inspection_id đã có repair sẽ trả resource có sẵn nếu vehicle_id khớp, kể cả caller dùng idempotency key mới; response vẫn là 201 theo route hiện tại.

POST thủ công chưa kiểm inspection có tồn tại/FAIL qua Inspection Service; caller chịu trách nhiệm tham chiếu đúng. Description khác với repair hiện có không ghi đè record. Vehicle_id khác cho inspection đã dùng trả 409 `inspection_vehicle_conflict`.

PATCH chỉ nhận IN_PROGRESS/COMPLETED/CANCELLED và phải tuân theo state machine. Không PATCH description/coverage. NotificationRead gồm id, vehicle_id, repair_id, channel, message, status, created_at, updated_at; lab trả LOG/SIMULATED.

## 6. Idempotency và retry contract của client

Một key đại diện cho **một ý định tạo**. Payload hash được tính trên model đã normalize/default, không trên raw bytes HTTP. Redis completed result là fast path; ledger PostgreSQL bảo đảm khi Redis mất dữ liệu.

| Tình huống | Kết quả | Client nên làm |
|---|---|---|
| Cùng key + payload tương đương | 201, body snapshot lần tạo đầu | Dùng ID cũ; GET để xem trạng thái mới |
| Cùng key + payload khác | 409 idempotency_key_reused | Sửa lỗi caller; chỉ dùng key mới cho ý định mới |
| 503 hoặc client timeout khi create | Kết quả có thể chưa rõ với client | Retry cùng key/payload, backoff hữu hạn |
| 409 vehicle_projection_not_ready / warranty_projection_not_ready | Domain event xe hoặc CDC warranty chưa đến Inspection | Chờ ngắn và retry cùng key; có deadline |
| 422 | Request contract sai | Sửa input, không retry mù |
| POST vehicle/warranty timeout | Không có API idempotency-key contract | Reconcile bằng VIN/warranty list và xử lý unique conflict |

Idempotency result giữ trạng thái lúc tạo: inspection retry có thể trả PENDING sau khi GET cùng resource đã COMPLETED. Redis TTL hết không làm mất durable reservation. Lab chưa có tenant/principal trong scope.

## 7. Error response

Các lỗi do domain/shared handlers xử lý dùng:

```json
{
  "error": {
    "code": "dependency_unavailable",
    "message": "Warranty lookup unavailable; coverage remains unknown and no repair was committed",
    "request_id": "583364bc-d7e5-4717-870f-1a682a7c3943"
  }
}
```

| HTTP | Codes hiện có | Ý nghĩa |
|---:|---|---|
| 404 | vehicle_not_found, warranty_not_found, inspection_not_found, repair_not_found, warranty_not_ready | Resource không có hoặc warranty chưa được quan sát |
| 409 | constraint_conflict, idempotency_key_reused, invalid_transition, vehicle_not_ready, vehicle_projection_not_ready, warranty_projection_not_ready, inspection_completed, completion_conflict, inspection_vehicle_conflict | Conflict dữ liệu/trạng thái hoặc eventual dependency |
| 422 | validation_error | Pydantic/path/query/header validation |
| 503 | database_unavailable, dependency_unavailable | Dependency/pool/lock transient error; có Retry-After: 2 |
| 500 | internal_error | Lỗi chưa dự kiến; cần kiểm log |

Framework-level 404 cho path không tồn tại và 405 có thể dùng `{"detail":...}` của FastAPI/Starlette; chưa được normalize bởi handler riêng. Unexpected 500 có thể thiếu context/headers khi lỗi thoát middleware, vì vậy client không nên phụ thuộc tuyệt đối vào request_id ở nhánh này.

## 8. Operations endpoints

Mỗi service có GET `/health` trả status alive, service, instance_id; GET `/ready` trả 200 ready hoặc 503 degraded với checks postgres/redis/kafka/workers. Readiness không xác nhận một workflow đã hoàn tất và không thay kiểm tra consumer lag.

Các `/lab/*` chỉ tồn tại khi LAB_MODE=true; chi tiết và giới hạn trong [Operations](OPERATIONS.md). OpenAPI phản ánh các route opt-in khi application đang chạy với cấu hình đó.

## 9. Source of truth

Contracts trong tài liệu được đối chiếu với router/schema của [Vehicle](../services/vehicle-service/app/api/routes.py), [Warranty](../services/warranty-service/app/api/routes.py), [Inspection](../services/inspection-service/app/api/routes.py), [Repair](../services/repair-service/app/api/routes.py) và [shared error/middleware](../common/platform_common/api.py). JSON OpenAPI sống là nguồn kiểm kiểu/required fields chính xác khi implementation thay đổi.

## Internal REST, workflow và metrics

| Method | Path | Contract |
|---|---|---|
| POST | B `/internal/warranties` | Body vehicle_id UUID, vehicle_created_at datetime; 201 WarrantyRead. Retry dedupe theo vehicle/type DEFAULT |
| GET | B `/internal/warranties/vehicle/{vehicle_id}/coverage` | Coverage tại primary; D dùng endpoint này |
| GET | C `/inspections/workflows/{vehicle_id}` | READY / WAITING_VEHICLE / WAITING_WARRANTY, flags, warranty IDs và source LSN; 404 nếu chưa có input |
| GET | Mọi API `/metrics` | Prometheus exposition format, không đưa vào business RPS |

Internal là ranh giới sử dụng, chưa phải authentication boundary. Lab chưa có mTLS/service auth. Vehicle POST 201 xác nhận vehicle+outbox+REST command durable; B lỗi thì command PENDING được retry. Inspection POST yêu cầu đủ cả domain vehicle và CDC warranty, trả 409 tương ứng khi còn thiếu input. InspectionRead và RepairRead thêm nullable warranty_id cho dữ liệu cũ.
