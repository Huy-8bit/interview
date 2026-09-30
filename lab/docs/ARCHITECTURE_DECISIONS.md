# Architecture Decision Records

[Mục lục](README.md) · [System Design](SYSTEM_DESIGN.md)

Các quyết định dưới đây mô tả implementation hiện tại. “Xem xét lại khi” là điều kiện để mở thiết kế mới; không có nghĩa phương án thay thế đã được triển khai.

## ADR-001 — Bốn domain service, database per service

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Vehicle, Warranty, Inspection, Repair có quy tắc và vòng đời khác nhau; bài lab cần làm rõ ownership và consistency qua network.

**Quyết định:** bốn FastAPI applications, bốn PostgreSQL database/role. Customer cơ bản nằm trong Vehicle; Notification thuộc Repair. Không tạo customer/notification service thứ năm.

**Phương án khác:** một modular monolith với transaction chung dễ vận hành hơn; shared DB microservices giảm chi phí integration nhưng làm mờ ownership và coupling schema.

**Hệ quả:** không có cross-DB FK/JOIN; reference validation/projection phải explicit, eventual consistency hiện rõ. Cùng PostgreSQL instance tiết kiệm tài nguyên lab nhưng vẫn là một failure domain hạ tầng.

**Xem xét lại khi:** domain/customer/notification có lifecycle hoặc ownership đội ngũ độc lập; deployment/HA requirements vượt mô hình laptop. Tách thêm domain sẽ thay đổi giới hạn bốn service của bài lab.

## ADR-002 — Event choreography kết hợp coverage REST

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Tạo xe cần fan-out sang nhiều domain; tạo repair cần quyết định coverage hiện tại.

**Quyết định:** Kafka cho business facts, REST cho `Repair → Warranty active lookup`. Không có orchestrator hoặc saga compensation.

**Phương án khác:** REST chain toàn bộ luồng đơn giản với caller nhưng cộng latency/coupling availability; copy toàn bộ warranty sang Repair giảm synchronous dependency nhưng tăng vấn đề stale/out-of-order projection.

**Hệ quả:** HTTP success là local commit; downstream cần polling/observability. Warranty outage chặn repair creation mới nhưng không chặn inspection complete. Repair lưu coverage snapshot, không xét chính sách claim backdated.

**Xem xét lại khi:** cần coverage tại thời điểm inspection, workflow nhiều bước có compensation, hoặc latency/availability target buộc bỏ synchronous lookup.

## ADR-003 — Polling transactional outbox

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Business row và Kafka message không nằm trong một transaction chung.

**Quyết định:** Business + outbox insert commit cùng DB; task lấy row với FOR UPDATE SKIP LOCKED, send/ACK, rồi mark PUBLISHED. Pending retry không giới hạn số attempt, backoff có cap.

**Phương án khác:** direct publish sau commit có thể mất event; publish trước commit có thể phát sự kiện cho dữ liệu rollback; distributed transaction phức tạp; CDC/Debezium có chi phí hạ tầng và vận hành riêng.

**Hệ quả:** thêm bảng/worker, polling delay, DB connection/row lock bị giữ khi gửi network. Crash giữa ACK và mark gây duplicate cần consumer dedupe. Per-aggregate head-of-line khi event cũ pending là trade-off có chủ đích.

**Xem xét lại khi:** throughput/latency đo thực cho thấy polling/lock là bottleneck, hoặc đội ngũ đủ khả năng vận hành CDC và xử lý schema/WAL/connector recovery.

## ADR-004 — At-least-once và PostgreSQL processed ledger

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Consumer có thể crash sau business commit trước source offset commit, hoặc nhận duplicate ở nhiều execution.

**Quyết định:** Manual offset commit sau DB transaction. INSERT reservation vào processed_events trước handler, cùng transaction với business/outbox; unique natural keys bổ sung lớp chống duplicate nghiệp vụ.

**Phương án khác:** auto-commit có cửa sổ mất xử lý; Redis-only dedupe mất correctness khi TTL/eviction/outage; Kafka exactly-once transactions không tự bao business SQL transaction trong cấu hình này.

**Hệ quả:** ledger tăng theo thời gian; cần retention/replay policy. Đổi consumer group cũng đổi namespace ledger. Không tuyên bố distributed exactly-once.

**Xem xét lại khi:** có external side effects không nằm trong DB transaction; cần delivery ledger/provider idempotency riêng, không chỉ thêm một log vào handler.

## ADR-005 — Redis là lớp hỗ trợ, PostgreSQL là lớp correctness

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Cache, fast API retry và distributed lock giúp giảm công việc lặp, nhưng Redis có TTL/restart/eviction.

**Quyết định:** Cache-aside với generation guard; Redis processing/completed idempotency state; token lock có lease. Durable idempotency reservation và business uniqueness nằm ở PostgreSQL; Redis down cho phép fallback.

**Phương án khác:** Chỉ dùng DB đơn giản hơn nhưng retry/cache chậm hơn; Redis-only coordination không đủ dài hạn; distributed locking phức tạp không thay thế transaction invariants.

**Hệ quả:** hai lớp state cần hiểu rõ; cache vẫn có stale window sau DB commit trước invalidate. Lease không có renewal/fencing; worker quá lease vẫn phải an toàn nhờ DB.

**Xem xét lại khi:** cần strict read-after-write, cache size/generation metadata quá lớn hoặc idempotency scope phải tách tenant/principal.

## ADR-006 — Retry inline hữu hạn và DLQ theo topic nguồn

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Cần thấy retry/poison-message behavior mà không dựng nhiều scheduler/topic stages.

**Quyết định:** Handler retry 1/2/4/8 giây, hết budget gửi source-topic-dlq và chờ ACK trước commit offset. Lưu raw bytes, original event, source location và consumer.

**Phương án khác:** Retry topics/parking-lot scheduler giảm head-of-line blocking nhưng thêm routing/order/dedupe requirements; retry vô hạn một poison record có thể chặn tiến triển lâu dài.

**Hệ quả:** một record lỗi làm chậm các partition worker sở hữu. Permanent/transient classification chưa chi tiết; DLQ cần operator và có thể duplicate. Source topic có nhiều group thì DLQ phải phân biệt consumer.

**Xem xét lại khi:** lag/SLO không chấp nhận retry inline, lỗi tạm thời thường kéo dài hơn budget, hoặc cần replay tự động có rate limit/audit.

## ADR-007 — API và background tasks chung process trong lab

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Host chỉ cần Docker, bài lab phải gọn và dễ theo dõi bốn application.

**Quyết định:** FastAPI lifespan tạo shared client/pool và asyncio outbox/consumer/expiry tasks. Một uvicorn process/container; shared library được copy vào từng image lúc build.

**Phương án khác:** API/worker deployments riêng tách scaling/failure domain nhưng tăng entrypoint/config và số container vận hành. Copy hạ tầng code vào mỗi service độc lập giảm shared package coupling nhưng tăng drift/sửa lỗi lặp.

**Hệ quả:** consumer crash restart cả API; pool contention giữa requests/workers; tăng replica đồng thời tăng cả API/outbox/consumer và DB connection budget. Shared package không chứa domain models của service khác.

**Xem xét lại khi:** workload API/consumer có scaling profile khác, CPU-bound jobs chặn event loop hoặc rollout cần failure isolation riêng.

## ADR-008 — Coverage unavailable không được coi là uncovered

**Trạng thái:** đã áp dụng.

**Bối cảnh:** 404 warranty có thể do event chưa tới; network failure không chứng minh xe hết bảo hành.

**Quyết định:** Chỉ nhận false từ một Coverage response hợp lệ cho đúng vehicle. Mọi lookup thất bại sau retry raise TransientError; creation transaction rollback. API trả 503, consumer retry rồi DLQ.

**Phương án khác:** Tạo repair với coverage UNKNOWN rồi reconcile sau có thể tăng availability nhưng cần trạng thái pending, rule notification/billing và retry workflow mới. Mặc định false sẽ đưa ra kết luận nghiệp vụ sai.

**Hệ quả:** API/consumer giữ DB transaction khi gọi REST; connection usage tăng khi upstream chậm. Lab không tạo phiếu pending coverage và không có circuit breaker.

**Xem xét lại khi:** business cần nhận repair ngay cả lúc Warranty down, hoặc cần audit warranty ID/checked_at/terms version. Khi đó phải mở rộng schema/state machine và test unknown→resolved transitions.
