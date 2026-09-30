# Development và hướng dẫn đọc code

[Mục lục](README.md) · [System Design](SYSTEM_DESIGN.md) · [Architecture Decisions](ARCHITECTURE_DECISIONS.md)

## 1. Bản đồ source

| Muốn hiểu/thay đổi | Đọc file |
|---|---|
| CLI startup progress | [up.sh](../scripts/up.sh), [Getting Started](GETTING_STARTED.md); từng API dùng [start.sh](../scripts/start.sh) để chạy migration trước Uvicorn |
| Startup và composition | `services/<service>/app/main.py`, [app factory](../common/platform_common/api.py) |
| Env và timeout/pool budgets | [config.py](../common/platform_common/config.py), [db.py](../common/platform_common/db.py), [runtime.py](../common/platform_common/runtime.py) |
| Vehicle cache và mutation | [vehicles.py](../services/vehicle-service/app/services/vehicles.py) |
| Warranty creation/expiry/coverage | [warranties.py](../services/warranty-service/app/services/warranties.py) |
| Inspection completion | [inspections.py](../services/inspection-service/app/services/inspections.py) |
| Repair + notification transaction | [repairs.py](../services/repair-service/app/services/repairs.py) |
| HTTP integration thật | [warranty_client.py](../services/repair-service/app/infrastructure/warranty_client.py) |
| Envelope và durable publish intent | [events.py](../common/platform_common/events.py), [outbox.py](../common/platform_common/outbox.py) |
| Consumer retry/dedupe/offset/DLQ | [consumer.py](../common/platform_common/consumer.py) |
| API idempotency | [idempotency.py](../common/platform_common/idempotency.py) |
| Cache Lua và token lock | [redis.py](../common/platform_common/redis.py) |
| Request/event context và JSON logs | [context.py](../common/platform_common/context.py), [logging.py](../common/platform_common/logging.py) |

`common/platform_common` chứa hạ tầng, không chứa business models shared giữa domain. Từng service được build từ root context để copy common library nhưng chạy với app package riêng. Nếu sửa common, rebuild các service bị ảnh hưởng.

## 2. Chạy và kiểm tra thay đổi

```sh
make up
make test
make lint
make demo
```

Không bắt buộc Python host. Khi không có Make, chạy service tests trong container và root suite trong toolbox như hướng dẫn README. Test service dùng schema PostgreSQL tạm; integration tests dùng HTTP/Kafka/Redis thật và để lại data UUID/VIN mới. Không thay bằng SQLite vì semantics ON CONFLICT/locks/JSONB là một phần bài lab.

Test timeout trong Repair có MockTransport để điều khiển lỗi cục bộ. Fault drill `chaos_verify.py` bổ sung test giữa service thật; không chạy fault drill song song với suite thường. Kết quả giai đoạn ban đầu ở [Validation](VALIDATION.md); phiên bản cluster và các bài failover có báo cáo riêng ở [Cluster Validation](CLUSTER_VALIDATION.md).

## 3. Thêm một business operation

1. Xác định service sở hữu invariant và trạng thái hợp lệ; cập nhật API/Data Model docs trước khi sửa behavior.
2. Thêm request/response schemas; phân biệt omitted và null nếu là PATCH.
3. Business layer mở hoặc nhận session của outer transaction. Repository không tự commit giữa workflow.
4. Dùng DB constraint/row lock để bảo vệ race; không coi Redis lease là guarantee.
5. Nếu phát event, enqueue cùng session trước commit. Không gọi Kafka trực tiếp sau database write.
6. Nếu là create cần client retry an toàn, dùng idempotency helper với scope ổn định và response serialize JSON.
7. Kiểm happy path, conflict/rollback và retry/concurrency phù hợp invariant mới; update contracts/diagrams.

Ví dụ thêm repair.completed event: phải cân nhắc transition terminal idempotent, payload/version, enqueue chỉ một lần trong cùng transaction PATCH, xử lý consumer cũ bỏ qua type mới và cập nhật [event catalog](EVENT_CONTRACTS.md). Hiện event đó **chưa tồn tại**.

## 4. Thêm consumer handler

Handler signature hiện tại là `async handler(session, event, runtime)`. `process_event` đã sở hữu transaction và processed reservation; handler không commit session riêng và không mở một DB transaction khác để lưu cùng business action.

Đăng ký event type trong `app/messaging/handlers.py`. Topic subscription được suy từ phần trước dấu chấm của event type. Cùng consumer group để scale replicas; group mới là delivery/ledger namespace mới, cần quyết định replay có chủ đích.

External side effect như gửi email không được bảo vệ chỉ bằng processed DB marker. Nếu gửi email rồi SQL rollback, retry có thể gửi lại. Dùng delivery outbox/provider idempotency và quyết định audit/retry contract trước khi bổ sung integration.

## 5. Sửa schema và migration

Migrations runtime đặt trong từng service. Initial revision gọi DDL common v1 cố định rồi tạo business tables. Không sửa initial revision đã được deploy để áp dụng thay đổi mới.

Với developer có Python environment tùy chọn:

```sh
# Sau khi cấu hình WRITE_DATABASE_URL tới database phát triển riêng
# và cài dependencies + PYTHONPATH thích hợp:
# cd services/vehicle-service
# alembic revision --autogenerate -m "describe schema change"
```

Docker workflow không cần Python host: mount thư mục service vào một container one-off để revision mới được lưu về source. Chạy từ root, chỉ dùng trên database phát triển của lab:

```sh
docker compose run --rm --no-deps \
  --user "$(id -u):$(id -g)" \
  -v "$PWD/services/vehicle-service:/app" \
  vehicle-service alembic revision --autogenerate -m "describe schema change"
```

Review generated DDL trước khi upgrade: rename thường có thể bị suy ra thành drop/add; backfill/check NOT NULL/unique trên dữ liệu hiện hữu cần kế hoạch riêng. Code chưa có canary migration hoặc zero-downtime rollout framework.

```sh
docker compose up -d --build vehicle-service
docker compose exec vehicle-service alembic current
docker compose exec vehicle-service alembic check
```

Test fixture create_all không chứng minh migration từ revision trước chạy tốt trên dữ liệu lớn. Với schema change, kiểm upgrade trên DB disposable có dữ liệu đại diện; không chạy downgrade phá dữ liệu đang dùng chỉ để kiểm.

## 6. Invariants và test tương ứng

| Behavior | Test hiện có |
|---|---|
| VIN unique, cache miss/hit/invalidation/generation | [test_vehicle.py](../services/vehicle-service/tests/test_vehicle.py) |
| Outbox rollback/retry/order | [test_outbox.py](../services/vehicle-service/tests/test_outbox.py) |
| Concurrent delivery, natural uniqueness, expiry | [test_warranty.py](../services/warranty-service/tests/test_warranty.py) |
| Reversed projection order, API retry, completion | [test_inspection.py](../services/inspection-service/tests/test_inspection.py) |
| Repair/notification uniqueness, HTTP timeout rollback | [test_repair.py](../services/repair-service/tests/test_repair.py) |
| Actual HTTP workflow/cache/coverage | [test_api_flow.py](../tests/integration/test_api_flow.py) |
| Kafka duplicate, retry and DLQ ACK/offset | [test_kafka.py](../tests/integration/test_kafka.py) |
| Cluster RF/ISR, slots, replica links, lock token và discovery fallback | [test_clusters.py](../tests/integration/test_clusters.py) |
| Live node failure và consumer rebalance | [cluster_drills.sh](../scripts/cluster_drills.sh), [cluster_verify.py](../scripts/cluster_verify.py) |
| Health and database credential isolation | [test_operations.py](../tests/integration/test_operations.py) |

Các test này không phải performance test hoặc chứng minh mọi interleaving của distributed system. Đọc failure design để biết crash windows và giới hạn còn lại; đo tải riêng nếu thay đổi pool/worker/timeout.

## 7. Cập nhật và render tài liệu

Markdown là source chính. Mỗi Mermaid block trong `docs/*.md` có một comment `%% diagram: unique-name`; không đổi ID chỉ để thay layout vì ID là tên artifact/link.

```sh
# Kiểm links và sự khớp giữa Markdown / source .mmd / SVG đã lưu
make docs-check
# Extract Mermaid và render lại SVG; không khởi động stack nghiệp vụ
make docs-render
```

Hai target dùng Docker. `scripts/docs.py` chạy bằng Python standard library trong container để extract/check; `scripts/render_docs.sh` dùng image Mermaid CLI đã pin để render. Không thêm application mới vào Compose.

Artifacts ở `docs/diagrams/`: SVG, source `.mmd`, manifest với SHA-256 source và gallery. Check xác nhận links/files, source hash và SVG XML; render bằng Mermaid CLI mới là bước parse Mermaid thật. Nếu sửa Mermaid, chạy render trước check để artifact không stale.

Công cụ render dựa trên [Mermaid CLI chính thức](https://github.com/mermaid-js/mermaid-cli), xuất SVG từ `.mmd`; không gửi code/tài liệu tới Figma hay dịch vụ xuất bản. SVG được lưu cùng docs để người đọc xem được khi Markdown viewer không hỗ trợ Mermaid.

## 8. Giới hạn cần giữ rõ khi mở rộng

- Thay đổi coverage semantics cần xét thời điểm kiểm định, thời điểm xử lý, lưu bằng chứng lookup và policy update repair đã có.
- Tách API/worker cần entrypoint mới và readiness phù hợp; tăng replicas hiện tại tăng cả tasks và connection pools.
- Nếu thêm tenant, phải scope cả API idempotency, cache/lock key, authorization và unique business rules.
- Nếu thêm auth/PII, kiểm log và DLQ payload retention; correlation ID không phải authorization token.
- Trước cleanup ledger/outbox, xác định retry/replay horizon và chiến lược restore, tránh biến replay thành side effect mới.

## 9. REST traffic worker

[traffic_generator](../traffic_generator/worker.py) là package độc lập, image [Dockerfile.traffic](../Dockerfile.traffic) chỉ có HTTPX/Pydantic. Không import runtime DB/Redis/Kafka vào worker. Flow giữ correlation ID và stable VIN/key qua retry; metrics dùng cửa sổ latency hữu hạn. Thêm API step phải tôn trọng flow timeout, cancellation và stable mutation intent.

Unit tests [test_traffic_generator.py](../tests/unit/test_traffic_generator.py) dùng HTTPX MockTransport để kiểm retry budget, 4xx, timeout sau commit/reconcile, metrics và flow failure isolation. `make traffic-test` dùng [observer](../scripts/traffic_verify.py) ngoài worker đọc Kafka để đối chiếu dữ liệu thật. `make traffic-drills` do shell orchestrator dừng/restore infrastructure; worker không có Docker socket. `make test` pause/resume traffic để bài integration cũ có thể kiểm outbox/lag hội tụ.

Vehicle migration 0002 thêm nullable `simulation_run_id`; header/run guard bảo vệ dữ liệu thường trong endpoint DELETE mô phỏng. Nếu mở rộng xóa nghiệp vụ, phải thiết kế event/cascade/retention riêng thay vì bỏ guard hiện tại.
