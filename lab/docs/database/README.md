# Cẩm nang cơ sở dữ liệu

> Bộ tài liệu này giải thích cách ứng dụng lưu, đọc, đồng bộ và bảo vệ dữ liệu. Nội dung được đối chiếu với các bản migration tạo bảng, các lớp ánh xạ đối tượng của Python và mã xử lý thật. Migration là căn cứ chính để xác định schema đã triển khai; mã service và worker cho biết schema được sử dụng như thế nào.

## Thứ tự đọc

1. [Tổng quan hệ thống cơ sở dữ liệu](SYSTEM_OVERVIEW.md): bốn database, quyền sở hữu dữ liệu, đường đọc/ghi và ranh giới nhất quán.
2. [Hành vi và giao dịch](BEHAVIOR.md): từng luồng nghiệp vụ, thời điểm commit, xử lý lỗi và khôi phục.
3. [Bảng và chỉ mục](TABLES_AND_INDEXES.md): bảng, cột, kiểu dữ liệu, khóa, ràng buộc và chỉ mục theo từng database.
4. [Danh mục truy vấn](QUERY_CATALOG.md): query đang chạy trong API, worker, consumer, health check và metrics; giải thích mục đích và hệ quả.

## Phạm vi và cách đọc

- Phạm vi gồm bốn database: `vehicle_db`, `warranty_db`, `inspection_db`, `repair_db`; trong đó có bảng dùng chung, bảng nghiệp vụ và `cdc_heartbeat`.
- Query minh họa được suy ra từ mã SQLAlchemy. Chỉ câu lệnh xuất hiện qua `text()` hoặc trong migration mới là SQL viết trực tiếp. Tài liệu sẽ đánh dấu rõ khác biệt này.
- Tài liệu mô tả schema khai báo trong migration, không khẳng định volume đang chạy đã ở đúng revision. Dùng `alembic current` và `alembic check` để xác nhận môi trường.
- Không có khóa ngoại hoặc phép nối giữa các database. ID tham chiếu giữa service chỉ là giá trị logic; hai khóa ngoại nội bộ là `notifications.repair_id → repair_requests.id` và `inspection_reports.inspection_id → inspections.id`.
- Có chỉ mục không đồng nghĩa PostgreSQL chắc chắn chọn chỉ mục đó. Kiểm tra bằng `EXPLAIN (ANALYZE, BUFFERS)` trên dữ liệu đại diện; lệnh này thực thi truy vấn nên không chạy tùy tiện trên truy vấn ghi hoặc dữ liệu production.
- Khi schema đổi, cập nhật tài liệu cùng migration và chạy `make docs-check`.

## Từ viết tắt và thuật ngữ

Các trang chi tiết dùng một số tên chuẩn trong PostgreSQL và tên trạng thái/event giống hệt code. Bảng này khai triển từ viết tắt và giải thích nghĩa tiếng Việt; chữ trong dấu backtick là tên chính xác cần giữ để tìm được trong repository.

| Thuật ngữ | Nghĩa trong bộ tài liệu |
|---|---|
| API | Application Programming Interface: giao diện để chương trình khác gọi chức năng của service |
| ACK | Acknowledgement: xác nhận broker đã nhận message; không tự commit transaction PostgreSQL |
| AMQP | Advanced Message Queuing Protocol: giao thức message queue mà RabbitMQ hỗ trợ |
| CDC | Change Data Capture: đọc các thay đổi đã commit từ transaction log rồi phát thành record |
| DDL | Data Definition Language: câu lệnh tạo/sửa schema, bảng, khóa và chỉ mục |
| FK | Foreign Key: khóa ngoại bảo đảm một giá trị tham chiếu tới row tồn tại trong cùng database |
| HTTP | Hypertext Transfer Protocol: giao thức truyền request/response của API web |
| ID | Identifier: mã định danh của một đối tượng hoặc row |
| JSONB | Kiểu JSON nhị phân của PostgreSQL, hỗ trợ lưu và truy vấn cấu trúc JSON |
| LSN | Log Sequence Number: vị trí byte trong Write-Ahead Log; không phải event ID |
| ORM | Object-Relational Mapping: ánh xạ lớp Python thành bảng và câu truy vấn SQL |
| PDF | Portable Document Format: định dạng tài liệu được lưu trong report |
| PK | Primary Key: khóa chính, nhận diện duy nhất một row |
| REST | Representational State Transfer: kiểu thiết kế giao diện HTTP dùng tài nguyên và method chuẩn |
| SHA-256 | Secure Hash Algorithm 256-bit: hàm băm dùng kiểm tra nội dung PDF |
| SQL | Structured Query Language: ngôn ngữ truy vấn cơ sở dữ liệu quan hệ |
| UUID | Universally Unique Identifier: mã định danh 128-bit được dùng cho nhiều khóa trong hệ thống |
| WAL | Write-Ahead Log: nhật ký ghi trước, dùng khôi phục và chuyển thay đổi PostgreSQL |
| B-tree | Balanced tree: cấu trúc cân bằng PostgreSQL thường dùng cho chỉ mục so sánh và sắp xếp |
| `BYTEA` | Kiểu PostgreSQL lưu dữ liệu nhị phân, dùng cho bytes của PDF |
| `TIMESTAMPTZ` | Kiểu PostgreSQL lưu thời điểm có ngữ nghĩa múi giờ |
| `TEXT` | Kiểu PostgreSQL lưu chuỗi dài không khai báo giới hạn độ dài |
| Database | Cơ sở dữ liệu; mỗi service sở hữu database riêng |
| Transaction | Giao dịch nguyên tử: hoặc toàn bộ thay đổi commit, hoặc toàn bộ rollback |
| Commit / rollback | Xác nhận / hủy các thay đổi trong giao dịch |
| Primary / replica | Máy chủ PostgreSQL nhận ghi / máy chủ sao lưu nhận WAL và có thể phục vụ một số lần đọc |
| Index | Cấu trúc tra cứu phụ, đổi thêm dung lượng và chi phí ghi lấy tốc độ đọc |
| Outbox | Bảng lưu bền vững ý định phát event cùng transaction nghiệp vụ |
| Consumer / worker | Tiến trình nhận event / tiến trình chạy công việc nền |
| Idempotency | Tính chất retry cùng yêu cầu không tạo thêm kết quả nghiệp vụ |
| Projection | Bản đọc cục bộ được dựng từ dữ liệu của service khác |
| Query plan | Kế hoạch PostgreSQL chọn để thực hiện truy vấn |
| Snapshot | Ảnh chụp giá trị được ghi tại một thời điểm; không tự cập nhật theo nguồn |
| Unique constraint | Ràng buộc duy nhất, PostgreSQL không cho hai row có cùng giá trị khóa |

Tên cột, bảng, event, trạng thái và cấu hình trong dấu backtick là identifier chính xác trong repository, không dịch để có thể tìm trực tiếp trong code. Ví dụ `PENDING`, `GENERATED`, `inspection.failed`, `vehicle_id` là giá trị/tên máy đọc được, không phải từ viết tắt cần tự suy diễn.

## Nguồn code chính

- Schema chung: [migration_v1.py](../../common/platform_common/migration_v1.py), [models.py](../../common/platform_common/models.py).
- Domain schema: [vehicle migrations](../../services/vehicle-service/migrations/versions/0001_initial.py), [warranty migrations](../../services/warranty-service/migrations/versions/0001_initial.py), [inspection migrations](../../services/inspection-service/migrations/versions/0001_initial.py), [repair migrations](../../services/repair-service/migrations/versions/0001_initial.py).
- Runtime connection/pool: [db.py](../../common/platform_common/db.py), [runtime.py](../../common/platform_common/runtime.py), [config.py](../../common/platform_common/config.py).
- Background DDL CDC: [init-cdc.sh](../../infrastructure/postgres/init-cdc.sh).
- Tài liệu liên quan: [Data Model](../DATA_MODEL.md), [PostgreSQL & CDC](../POSTGRESQL_CDC.md), [Consistency and Failures](../CONSISTENCY_AND_FAILURES.md), [Operations](../OPERATIONS.md).