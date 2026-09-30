# Kết quả kiểm chứng bài lab — giai đoạn ban đầu

Báo cáo này giữ kết quả trước khi chuyển infrastructure sang cluster. Kết quả phiên bản hiện tại ở [Cluster Validation](CLUSTER_VALIDATION.md).

Ngày thực hiện: **2026-09-30**. Môi trường: Docker Engine 29.4.0, Docker Compose 5.1.2, Linux ARM64 trong Docker trên macOS. Ứng dụng chạy Python 3.12 trong image, PostgreSQL 16.9, Redis 7.4.4, Apache Kafka 3.9.1 KRaft.

## Kiểm thử tự động

| Bộ test | Số test | Nội dung |
|---|---:|---|
| Vehicle Service | 5 | Unique VIN, cache/invalidation/generation race, atomic outbox, rollback, retry tới Kafka thật, thứ tự pending event |
| Warranty Service | 3 | Concurrent duplicate delivery, natural uniqueness, rollback marker/business, expiry và coverage |
| Inspection Service | 2 | Projection đảo thứ tự, concurrent Idempotency-Key, Redis eviction, completion/outbox atomic |
| Repair Service | 2 | Duplicate consumer/API, một notification/outbox, HTTP timeout budget và rollback |
| Unit dùng chung | 3 | Canonical fingerprint, exponential backoff, event version |
| Integration toàn stack | 9 | API validation, E2E PASS/FAIL, coverage, Redis cache, idempotency, Kafka duplicates, DLQ, readiness, DB role isolation |
| **Tổng** | **24** | **Pass** |

Service tests dùng PostgreSQL schema riêng và Redis thật. Root integration tests dùng HTTP, PostgreSQL, Redis và Kafka của stack đang chạy. Riêng test timeout của HTTP client tại Repair Service dùng `httpx.MockTransport`; fault drill riêng xác nhận timeout giữa hai service thật.

## Fault drills đã thực thi

- Outbox bị buộc publish thất bại hai lần, giữ PENDING/attempts và sau đó gửi thành công.
- Cache cố ý chứa bản cũ với TTL 2 giây: quan sát trả stale rồi tự phục hồi từ DB.
- Warranty REST cố ý chậm 3 giây: Repair hết timeout/retry, trả 503 và không commit uncovered repair.
- Process Repair bị `os._exit(70)` ngay sau DB commit trước offset commit. Container restart và cùng event được nhận lại. Log có `lab_crash_after_db_commit_before_offset_commit` rồi `duplicate_event_skipped`; chỉ có một repair/notification.
- Giữ 10 connection trong pool mặc định: request DB trả 503 trong acquire timeout và phục hồi sau khi trả connection.
- Dừng Kafka: API vẫn commit xe/outbox; event PENDING có attempt lỗi; restart broker và outbox được publish.
- Dừng PostgreSQL: liveness vẫn 200, readiness và query DB trả 503; restart và phục hồi.
- Dừng Redis: GET xe bypass cache; retry cùng Idempotency-Key vẫn trả cùng inspection nhờ PostgreSQL; restart và phục hồi.
- Dừng Warranty Service: Repair API trả 503, không tạo repair; restart và readiness phục hồi.

Kafka poison-message test đã quan sát DLQ thật sau 4 retry, kiểm tra original event/raw bytes/source/reason và source offset được commit sau DLQ ACK. Test concurrent worker dùng 4–6 asyncio task, mỗi task một PostgreSQL session độc lập.

Các hướng dẫn tăng consumer lag và chạy thêm consumer container với scatter duplicate có trong README; hai bài vận hành thủ công đó chưa được thực thi trong lượt xác nhận này. Cơ chế concurrent deduplication đã được kiểm thử ở mức transaction như mô tả trên.

## Build và hướng dẫn sử dụng

- Docker Compose khởi tạo tự động bốn database/role, chạy bốn Alembic migration history và tạo đủ 8 Kafka topics.
- Build đủ 4 service image và toolbox. Các service có health/readiness; Kafka UI phục vụ trên port 8080.
- Kiểm tra Python compile/import, Ruff và dependencies trong image.
- Đối chiếu SQLAlchemy metadata với schema bằng `alembic check` ở từng database.
- Chạy trực tiếp hai block curl trong mục API Examples của README: tạo/cập nhật xe, cache, inspection/idempotency, FAIL/repair/notification, PASS, warranty activate/expire.
- Chạy demo tự động và seed 100 xe bằng public APIs/event flow.

Tái chạy kiểm chứng:

```sh
make up
make test
make lint
make demo
make seed
make chaos-up
make test-chaos
sh scripts/outage_drills.sh kafka
sh scripts/outage_drills.sh postgres
sh scripts/outage_drills.sh redis
sh scripts/outage_drills.sh warranty-service
docker compose up -d --wait
```

Không phải benchmark/load/soak test hoặc đánh giá HA. Chưa kiểm thử riêng host x86_64, Kubernetes, auth/TLS hay recovery từ mất volume. Test/seed để lại dữ liệu mẫu trong stack; không xóa dữ liệu khi hoàn tất. Fault injection được tắt ở cấu hình thường.

## Kiểm chứng bộ tài liệu mở rộng

Trong lượt bổ sung tài liệu, không thay đổi business code và không chạy lại bộ test/fault drill ở trên. Các kiểm tra riêng cho docs:

- Render 25 Mermaid diagrams thành SVG bằng Mermaid CLI 11.4.2 trong Docker; xem preview các sơ đồ kiến trúc, sequence, ERD, state machine và consumer flow.
- Kiểm tra local links/anchors và tính đồng bộ Markdown → Mermaid source → SVG bằng manifest SHA-256 qua `make docs-check`.
- Đối chiếu đủ 19 endpoint trong bảng API với router của bốn service bằng Python AST.
- Parse thành công 6 JSON examples; kiểm tra cú pháp 24 shell examples bằng `bash -n`, không thực thi các lệnh gây outage/restore trong lượt viết docs.
- `scripts/docs.py` qua Python compile và Ruff; `scripts/render_docs.sh` qua `sh -n`.
