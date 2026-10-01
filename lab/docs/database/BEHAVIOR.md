# Hành vi dữ liệu và ranh giới giao dịch

Giao dịch (transaction) là nhóm thay đổi PostgreSQL commit hoặc rollback cùng nhau. Khi API trả thành công, điều đó thường chỉ xác nhận giao dịch ở database của service nhận request đã commit; event, CDC hoặc tác vụ nền có thể chưa xử lý xong.

## 1. Tạo xe, bảo hành mặc định và bản chiếu Inspection

1. Vehicle Service mở giao dịch trên `vehicle_db`. Nó chèn xe vào `vehicles`, event `vehicle.created` vào `outbox_events`, và yêu cầu gọi bảo hành vào `warranty_provision_requests` ở trạng thái PENDING. Cả ba thay đổi commit cùng nhau. Nếu một bước thất bại, không có xe được commit một mình.
2. Sau commit, worker chọn yêu cầu đến hạn và gọi Warranty Service qua REST. Khi lỗi, worker tăng số lần thử, lưu loại lỗi và đặt thời điểm thử tiếp theo. Yêu cầu vẫn nằm trong database nên process restart không làm mất nó. Warranty Service chống tạo lặp bằng khóa duy nhất `(vehicle_id, warranty_type)`.
3. Warranty Service ghi warranty vào `warranty_db`. Debezium đọc thay đổi từ Write-Ahead Log (WAL) logic của PostgreSQL rồi phát Change Data Capture (CDC) vào Kafka. Song song, Vehicle outbox phát event xe. Hai luồng không có thứ tự toàn cục; Inspection có thể nhận warranty trước hoặc xe trước.
4. Inspection consumer dùng advisory transaction lock theo vehicle ID để tuần tự hóa việc tạo/cập nhật `vehicle_references` và `vehicle_warranty_projection`. Upsert chỉ chấp nhận event mới hơn theo thời gian cập nhật hoặc checkpoint WAL/partition/offset. Khi nhận CDC delete, projection được giữ lại với `is_deleted=true` thay vì xóa hẳn, nhờ đó một snapshot cũ không làm sống lại warranty đã xóa.
5. Inspection đặt readiness thành READY khi đã thấy event xe và có ít nhất một warranty projection chưa bị xóa. Điều này chỉ xác nhận đủ dữ liệu để tạo inspection; không xác nhận warranty còn hiệu lực ngày hôm nay. Coverage vẫn do Warranty Service quyết định.

**Khi lỗi:** nếu Vehicle commit thành công nhưng Warranty REST lỗi, API create vehicle vẫn có thể trả thành công vì lệnh provision đã được lưu để retry. Nếu một trong hai input chưa đến Inspection, POST inspection trả conflict retryable thay vì đọc database khác trực tiếp.

Code: [vehicles.py](../../services/vehicle-service/app/services/vehicles.py), [warranty_provision.py](../../services/vehicle-service/app/services/warranty_provision.py), [handlers.py](../../services/inspection-service/app/messaging/handlers.py).

## 2. Tạo và hoàn tất inspection

- **Tạo:** service đọc `vehicle_references` theo khóa chính. Chỉ cho tạo khi `vehicle_seen=true` và `workflow_status='READY'`; warranty ID hiện có được sao chép vào inspection như một tham chiếu lịch sử.
- **Retry request:** `execute_idempotent` băm khóa và payload. Trong transaction, `INSERT ... ON CONFLICT DO NOTHING` giành quyền xử lý khóa; nếu đã có row thì so hash. Cùng khóa/cùng payload trả response đã lưu, khác payload trả 409. Redis là cache tăng tốc, còn `idempotency_records` là nguồn bền vững.
- **Cập nhật/hoàn tất:** service đọc inspection bằng `SELECT ... FOR UPDATE`. Khóa hàng ngăn hai transaction cùng chuyển trạng thái đồng thời. Inspection COMPLETED là bất biến; gọi complete lại chỉ được chấp nhận nếu result, reason và notes phù hợp với kết quả đã commit.
- **Commit hoàn tất:** một transaction cập nhật result/status/completed_at, tạo đúng một `inspection_reports` do unique inspection ID bảo vệ, và ghi event PASS/FAIL vào outbox. Nếu transaction rollback, không có report job và event cho trạng thái chưa commit. HTTP response không đợi render PDF.
- **Phân phối report:** dispatcher chọn report PENDING đến hạn theo ưu tiên cao trước rồi thời gian tạo, dùng `FOR UPDATE SKIP LOCKED` để các bản sao API không claim cùng row. Nó giữ transaction trong lúc chờ RabbitMQ publisher confirm rồi đặt QUEUED. Nếu broker đã nhận task nhưng DB commit thất bại, cùng task ID có thể được phát lại.
- **Render report:** worker khóa row theo inspection ID, kiểm tra trạng thái và inspection COMPLETED, đánh dấu PROCESSING/tăng attempts rồi commit trước khi render. Không giữ row lock trong thời gian render để tránh khóa lâu và chiếm connection. Sau render, worker mở transaction khác, khóa row lại và kiểm tra GENERATED lần nữa. Worker thắng cuộc lưu PDF, hash, metadata và event outbox; worker trùng trả duplicate.

**Trade-off:** worker có thể render cùng một PDF nhiều lần nếu task bị giao đồng thời, nhưng chỉ một transaction có thể commit kết quả cuối. Quy tắc này bảo vệ tính đúng đắn, không loại bỏ hoàn toàn CPU bị dùng lặp.

Code: [inspections.py](../../services/inspection-service/app/services/inspections.py), [dispatcher.py](../../services/inspection-service/app/reports/dispatcher.py), [tasks.py](../../services/inspection-service/app/reports/tasks.py).

## 3. Tạo, chuyển trạng thái và kiểm tra coverage bảo hành

- **Bảo hành mặc định:** Vehicle gửi request REST chứa thời điểm tạo xe. Warranty dùng ngày đó để tính start/end date, chèn trạng thái ACTIVE và outbox trong cùng transaction. Nếu request bị gửi lại sau khi response thất lạc, unique `(vehicle_id,warranty_type)` khiến code đọc row đã có và không phát event created lần hai.
- **Bảo hành mở rộng:** endpoint tạo EXTENDED/POWERTRAIN yêu cầu đã có warranty history; row bắt đầu PENDING. Các quy tắc transition được kiểm trong service và một phần được bảo vệ bằng CHECK constraint.
- **Kiểm tra coverage:** truy vấn lấy tất cả warranty của vehicle, sắp theo `created_at`; ứng dụng chọn bản đầu tiên có status ACTIVE và ngày UTC hiện tại nằm trong khoảng đóng `[start_date,end_date]`. Không có history trả 404 vì dữ liệu có thể chưa provision xong; có history nhưng không có row thỏa điều kiện trả `covered=false`. Hai kết quả mang ý nghĩa khác nhau.
- **Tự hết hạn:** worker chọn tối đa 100 warranty ACTIVE/PENDING có `end_date < ngày UTC hiện tại`, khóa hàng mà worker khác chưa khóa, chuyển EXPIRED và thêm event outbox. Hết hạn được xác định từ ngày ngay cả khi worker chưa chạy đúng thời điểm; trạng thái EXPIRED trong bảng có thể cập nhật trễ tối đa nhiều chu kỳ worker.

Coverage authority là Warranty Service. `vehicle_warranty_projection` trong Inspection phục vụ readiness và dữ liệu báo cáo, không dùng để quyết định Repair coverage. Hiện query coverage đọc toàn bộ history của vehicle rồi lọc ở Python; khi số loại/historical warranty tăng, nên đo chi phí và cân nhắc lọc ngày/trạng thái trong SQL.

Code: [warranties.py](../../services/warranty-service/app/services/warranties.py).

## 4. Tạo phiếu sửa chữa và lưu kết quả coverage

- Hai đường tạo repair là REST create và consumer của `inspection.failed`. REST dùng idempotency ledger; consumer dùng bảng `processed_events`. Unique `repair_requests.inspection_id` là hàng rào cuối cùng chung cho cả hai đường.
- Service tra repair theo inspection trước khi gọi Warranty. Nếu đã tồn tại và cùng vehicle, trả row cũ; không gọi Warranty lần nữa và không tạo notification/outbox lặp. Nếu vehicle khác, trả conflict.
- Nếu chưa có repair, service gọi Warranty REST để lấy coverage. Sau đó PostgreSQL insert repair bằng `ON CONFLICT DO NOTHING`, insert notification LOG và enqueue `repair.created` trong cùng transaction. Warranty request nằm ngoài transaction PostgreSQL; nếu REST lỗi thì transaction repair rollback. Nếu REST thành công nhưng insert gặp race/unique conflict, code đọc repair đã tạo bởi transaction kia.
- `warranty_covered` và `warranty_id` là snapshot lúc tạo repair. Row không lưu đầy đủ warranty terms hoặc thời điểm `checked_at`; do đó audit đầy đủ quyết định coverage về sau còn hạn chế.
- PATCH khóa repair row và chỉ cho OPEN → IN_PROGRESS/CANCELLED, IN_PROGRESS → COMPLETED/CANCELLED. Transition được kiểm ở service, không có trigger database. Việc đổi trạng thái hiện không phát event.
- Khi event `inspection.report.generated` đến, handler chỉ xử lý result FAIL. Nó khóa repair theo inspection ID rồi cập nhật số báo cáo, SHA-256 và thời gian render. Nếu không tìm thấy repair, handler log warning và vẫn hoàn tất event; đây là giả định dựa trên thứ tự outbox cùng vehicle, không phải cơ chế chờ/retry theo nghiệp vụ.

Code: [repairs.py](../../services/repair-service/app/services/repairs.py), [handlers.py](../../services/repair-service/app/messaging/handlers.py).

## 5. Mẫu xử lý khi có lỗi

| Điểm lỗi | Trạng thái có thể đã commit | Cách an toàn để tiếp tục |
|---|---|---|
| Trước commit business transaction | Không có thay đổi bền vững của transaction đó | Client/worker thử lại; không giả định một phần dữ liệu đã được ghi |
| Sau commit, trước khi publisher đọc outbox | Business row và event PENDING đã có | Publisher tiếp tục từ database, không tạo event identity mới |
| Kafka nhận event nhưng process chết trước khi đánh dấu PUBLISHED | Event có thể ở Kafka; outbox vẫn PENDING | Gửi lại cùng event ID; consumer ledger bỏ qua tác động trùng |
| Consumer commit database nhưng chưa commit Kafka offset | Business effect và processed marker đã có; Kafka có thể giao event lại | Marker trùng khiến handler bị bỏ qua; consumer commit offset tiếp theo |
| API commit xong nhưng response thất lạc | Resource và idempotency response có thể đã có | Gửi lại cùng Idempotency-Key và payload |
| RabbitMQ confirm task nhưng DB chưa lưu QUEUED | Task có thể đã vào queue; row vẫn PENDING | Dispatcher gửi cùng task ID; worker khóa report và dedupe khi commit |
| Redis không sẵn sàng | PostgreSQL vẫn giữ unique keys và ledgers | Tiếp tục qua DB; cache/lock là tối ưu hóa chứ không phải nguồn correctness |
| Kết nối mất đúng lúc COMMIT | Kết quả commit không xác định với caller | Tra cứu lại bằng cùng khóa nghiệp vụ/idempotency key; không kết luận rollback từ timeout |

Các ledgers bền vững hiện chưa có job dọn dẹp. Xóa marker quá sớm sẽ làm tăng rủi ro duplicate khi client retry hoặc Kafka replay; retention phải được thiết kế theo thời gian retry, replay và khôi phục backup. Chi tiết các cửa sổ crash trong [Consistency and Failures](../CONSISTENCY_AND_FAILURES.md).