# Thứ tự CLI và tiến độ khởi động

[Mục lục](README.md) · [Operations](OPERATIONS.md) · [Traffic Generator](TRAFFIC_GENERATOR.md)

## 1. Lần đầu chạy

Mở Docker Desktop (hoặc Docker Engine trên Linux), đợi engine sẵn sàng. Từ thư mục repository:

```sh
cd /Users/huynguyen/Desktop/poc/lab/lab
# Chỉ tạo .env khi chưa có; không ghi đè cấu hình đang dùng
[ -f .env ] || cp .env.example .env

# Một lệnh khởi động tất cả, tự xử lý dependency order
make up
# Không có make thì dùng: bash scripts/up.sh
```

Đợi dòng `READY Startup completed`. Không cần tự chạy từng PostgreSQL/Kafka/Redis service hoặc tạo connector thủ công. Traffic mặc định đã enabled với năm virtual users, nên không cần seed/demo để bắt đầu thấy dữ liệu.

## 2. Những bước hiện trên terminal

[Launcher](../scripts/up.sh) chạy tuần tự các bước dưới; trong một bước, Compose có thể start nhiều container song song. Đây là thứ tự của `make up`; dependency graph gốc của Compose vẫn giữ nguyên.

| Bước | Nội dung | Điều kiện báo OK |
|---|---|---|
| 01/10 | Docker Engine, Compose, cấu hình | Engine truy cập được, Compose hỗ trợ wait-timeout, config hợp lệ |
| 02/10 | Build bốn API và generator | Docker build exit 0 |
| 03/10 | PostgreSQL primary, sáu Redis nodes, ba Kafka brokers | Healthchecks của các container thành công |
| 04/10 | DB roles/physical slot, Redis cluster, Kafka topics | postgres-init, redis-cluster-init, kafka-init đều exit 0 |
| 05/10 | PostgreSQL replica | Healthcheck xác nhận hot standby đang recovery |
| 06/10 | Migration và bốn API | Alembic thành công và `/ready` của cả bốn API trả 200 |
| 07/10 | CDC publications/grants/replica identity | cdc-db-init exit 0 |
| 08/10 | Debezium Connect | Connect REST healthcheck thành công |
| 09/10 | Bốn connectors | debezium-init xác nhận connector và task RUNNING rồi exit 0 |
| 10/10 | Kafka UI và Traffic Generator | UI container running; generator heartbeat healthy hoặc scenario đã exit 0 |

Ví dụ hình thức log; thời gian thực tế phụ thuộc máy và image cache:

```text
[14:00:00] [01/10] RUNNING Docker Engine, Compose and configuration
[14:00:01] [01/10] OK      Docker Engine, Compose and configuration (1s)
...
[14:00:30] [04/10] RUNNING DB roles/slot, Redis Cluster, Kafka topics
WAIT kafka-init: state=running, health=none, elapsed=10s
WAIT kafka-init: state=running, health=none, elapsed=20s
...
[14:02:10] [04/10] OK      DB roles/slot, Redis Cluster, Kafka topics (100s)
...
[14:03:00] [10/10] READY   Startup completed in 180s. Log: .../startup.log
```

`RUNNING` là đang thực hiện; `WAIT` là còn chờ init/health; `OK` là bước đã đạt điều kiện thật; `FAILED` dừng tại bước lỗi. Script không dùng sleep cố định để kết luận thành công. Các init jobs hoàn tất đúng sẽ ở trạng thái `Exited (0)` trong `docker compose ps --all`; đây là kết quả bình thường.

Mỗi lần chạy lưu toàn bộ output vào **`artifacts/startup/<timestamp>-<pid>/startup.log`** và snapshot generator vào `traffic-status.json` cùng thư mục. Cuối lệnh in URL thực tế cho Swagger, Kafka UI và Connect, kể cả Repair được cấp cổng động.

`OK` của bước replica chỉ xác nhận healthcheck hot standby; chưa đo catch-up/byte lag. UI hiện chưa có HTTP healthcheck. Generator healthy có thể đang enabled=false; đọc snapshot `enabled`, `mode`, counters. `READY` là hoàn tất startup checks, chưa phải kiểm chứng toàn bộ business flow; dùng `make traffic-test` khi cần.

Timeout chờ health/init mặc định 600s mỗi lần chờ, có thể tăng bằng biến shell:

```sh
STARTUP_TIMEOUT_SECONDS=900 make up
```

Timeout này không giới hạn thời gian build/pull image của Docker. Launcher đọc biến từ shell; đặt trước lệnh như trên. Khi sửa cấu hình, chạy lại `make up`; các bước init kiểm cấu hình hiện hữu, không reset volumes. Không chạy hai phiên startup/fault drill đồng thời.

## 3. Xem hệ thống sau khi READY

```sh
make ps
make traffic-status
make traffic-logs
```

`traffic-logs` theo dõi liên tục; **Ctrl+C chỉ thoát màn hình logs**, container tiếp tục chạy. Mở [Kafka UI](http://localhost:8080), hoặc URL cuối lệnh startup nếu đã đổi port. Nhìn domain/CDC topics và consumer lag; [live guide](TRAFFIC_GENERATOR.md#7-quan-sát-realtime) có SQL/Redis/Connect commands.

Xem riêng startup/API logs ở terminal khác:

```sh
docker compose logs -f --tail=50 vehicle-service warranty-service inspection-service repair-service
# Init logs khi muốn biết topic/connector đang xử lý
docker compose logs -f --tail=30 kafka-init redis-cluster-init postgres-init cdc-db-init debezium-init
```

Bốn API có log `[startup][service][1/2]` cho Alembic RUNNING/OK/FAILED; `[2/2]` báo bắt đầu Uvicorn/lifespan. `/ready` và healthcheck mới quyết định API sẵn sàng. Các log này xuất hiện cả khi dùng trực tiếp `docker compose up --build`.

## 4. Kiểm chứng thêm — tùy chọn

Sau startup thành công, chạy tuần tự:

```sh
make db-check        # Streaming replication, slots, connectors, CDC topics
make cluster-check   # Kafka/Redis topology
make traffic-test    # Hai scenario PASS/FAIL, duplicate, cache và CDC
make test            # Unit/integration; tự pause rồi restore generator
```

`make traffic-scenario` chỉ chạy thêm một flow bên cạnh continuous traffic rồi exit. Muốn quan sát đúng một flow, chạy `make traffic-stop` trước, chạy scenario, sau đó `make traffic-start`.

Fault drills chỉ dùng khi muốn học outage; không phải bước bắt buộc để chạy lab. `make traffic-drills` cần generator đang chạy. Các bài cũ `make cluster-test`/`make db-test` cần dừng traffic trước rồi bật lại sau; xem [runbook](OPERATIONS.md#13-traffic-generator-đang-chạy).

## 5. Dừng và chạy lại

```sh
# Chỉ dừng việc tạo dữ liệu, vẫn giữ APIs và hạ tầng
make traffic-stop
# Bật lại generator
make traffic-start

# Dừng toàn bộ stack, giữ named volumes/dữ liệu
make down
# Lần sau chạy lại cùng một lệnh, có log tiến độ
make up
```

`make clean` có `down -v`, dùng khi chủ động muốn xóa dữ liệu lab; không nằm trong thứ tự khởi động thông thường.

## 6. Khi startup thất bại

Dòng `FAILED` chỉ rõ số bước, exit code, log file và lệnh xem logs của các service liên quan. Script không chạy các bước sau và không tự down/xóa dữ liệu để che lỗi.

```sh
docker compose ps --all
# Ví dụ lỗi bước 04: xem init job tương ứng
docker compose logs --tail=100 kafka-init
# Ví dụ lỗi bước 06: xem migration/readiness của API
docker compose logs --tail=100 vehicle-service
```

Sửa nguyên nhân rồi `make up` lại. Ctrl+C khi đang startup dừng phiên chờ; kiểm `make ps` vì những container đã được start có thể vẫn đang chạy. Nếu chỉ muốn logs tiến độ mà không thay thứ tự Compose, `docker compose up --build` vẫn hợp lệ, nhưng chỉ `make up`/`bash scripts/up.sh` có nhãn tổng thể 01/10…10/10 và file log của launcher.

Tham chiếu: [`compose up --wait`](https://docs.docker.com/reference/cli/docker/compose/up/) chờ running/healthy; [`compose logs --follow`](https://docs.docker.com/reference/cli/docker/compose/logs/) theo dõi output container. Launcher chờ init exit code riêng để phân biệt job đã hoàn tất với service đang chạy.

## 7. Kiểm chứng thay đổi

Ngày 2026-09-30, `make up` đã chạy đủ 10 bước từ stack dừng đến `READY`, exit 0 sau 452s trên máy lab tại thời điểm kiểm tra. Snapshot cuối ghi generator enabled=true, continuous, năm virtual users; cả bốn API có đủ log migration RUNNING/OK và Uvicorn startup. Thời gian này bao gồm build/init và phụ thuộc tải máy, không phải thời gian khởi động cam kết.

Ba test trong [test_startup_launcher.py](../tests/unit/test_startup_launcher.py) đều pass: init exit khác 0, init timeout, và continuous worker thoát 0 bất thường. Các test kiểm launcher dừng ở gate lỗi, giữ log chẩn đoán và không tự down/xóa container. Shell syntax, Python lint và liên kết tài liệu đã được kiểm tra.
