# Architecture Decision Records

[Mục lục](README.md) · [System Design](SYSTEM_DESIGN.md)

Các quyết định dưới đây mô tả implementation hiện tại. “Xem xét lại khi” là điều kiện để mở thiết kế mới; không có nghĩa phương án thay thế đã được triển khai.

## ADR-001 — Bốn domain service, database per service

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Vehicle, Warranty, Inspection, Repair có quy tắc và vòng đời khác nhau; bài lab cần làm rõ ownership và consistency qua network.

**Quyết định:** bốn FastAPI applications, bốn PostgreSQL database/role. Customer cơ bản nằm trong Vehicle; Notification thuộc Repair. Không tạo customer/notification service thứ năm.

**Phương án khác:** một modular monolith với transaction chung dễ vận hành hơn; shared DB microservices giảm chi phí integration nhưng làm mờ ownership và coupling schema.

**Hệ quả:** không có cross-DB FK/JOIN; reference validation/projection phải explicit, eventual consistency hiện rõ. Bốn database dùng chung primary–replica PostgreSQL để tiết kiệm tài nguyên; primary write endpoint và Docker host vẫn là failure domains chung.

**Xem xét lại khi:** domain/customer/notification có lifecycle hoặc ownership đội ngũ độc lập; deployment/HA requirements vượt mô hình laptop. Tách thêm domain sẽ thay đổi giới hạn bốn service của bài lab.

## ADR-002 — Event choreography kết hợp coverage REST

**Trạng thái:** đã áp dụng.

**Bối cảnh:** Tạo xe cần fan-out sang nhiều domain; tạo repair cần quyết định coverage hiện tại.

**Quyết định:** Kafka cho business facts, REST cho `Vehicle → Warranty provision` và `Repair → Warranty coverage lookup`. Không có orchestrator hoặc saga compensation.

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

## ADR-009 — Kafka ba node combined KRaft, RF=3 và min ISR=2

**Trạng thái:** Đã áp dụng, thay thế hạ tầng một broker của phiên bản lab ban đầu.

**Bối cảnh:** Cần quan sát partition leaders, ISR, quorum election và producer/consumer recovery khi mất node.

**Quyết định:** Ba broker/controller dùng chung cluster ID, voters cố định; business/DLQ có tối thiểu ba partitions, RF=3, min ISR=2, unclean election tắt. Mỗi node có log volume riêng; mọi client có ba bootstrap servers.

**Phương án khác:** Controller riêng tách failure domain và tài nguyên tốt hơn nhưng tăng container. Kafka transactions không thay thế PostgreSQL outbox/processed ledger.

**Hệ quả:** Chịu một node failure khi replica đồng bộ, mất hai node sẽ mất availability; cùng Docker host vẫn là failure domain chung. Tăng RAM/disk/CPU so với lab một broker. Startup chờ đủ nodes/init, không tự sửa RF của topic cũ có dữ liệu.

**Xem xét lại khi:** Cần chịu lỗi host/AZ, workload khiến controller tranh tài nguyên broker hoặc cần thay đổi quorum membership.

## ADR-010 — Redis Cluster sáu node, hash tags và DB fallback

**Trạng thái:** Đã áp dụng, thay thế Redis standalone của phiên bản đầu.

**Bối cảnh:** Cần học slot distribution, MOVED/ASK, master promotion và client recovery, trong khi cache Lua dùng nhiều key.

**Quyết định:** Ba master + ba replica; async RedisCluster client có sáu seed nodes; cache/generation hash tag theo vehicle ID; AOF và nodes.conf trên volume riêng. Node IP ổn định trên subnet Docker riêng, role không cố định. Deadline 2s mỗi thao tác, fallback DB giữ các invariants đã có.

**Phương án khác:** Sentinel cung cấp failover nhưng không shard 16.384 slots; single-master client không đáp ứng yêu cầu cluster routing. Một hash tag cho mọi key làm mất phân phối tải.

**Hệ quả:** Multi-key operations phải cùng slot; replica promotion có cửa sổ mất write đã ACK. Token lease không fencing, không có guarantee mutual exclusion xuyên async failover. DB unique/ledger/idempotency tiếp tục chịu trách nhiệm correctness. Subnet cần không trùng network/VPN đang dùng.

**Xem xét lại khi:** Cần Redis persistence/stronger consistency cho dữ liệu gốc, reshard online ở tải lớn hoặc đa vùng. Các thay đổi đó cần thiết kế consistency riêng, không chỉ tăng replica count.

## ADR-011 — Physical PostgreSQL replica, read opt-in, không tự promote

**Trạng thái:** đã áp dụng.

**Quyết định:** giữ PostgreSQL 16.9/data volume hiện có làm primary, bootstrap hot standby bằng pg_basebackup/physical slot. Tách writer/reader URL và reader role. Chỉ Vehicle detail GET opt-in eventual được route replica; lỗi query fallback read-only primary, stale 404 giữ nguyên và không cache. Các quyết định nghiệp vụ đọc primary.

**Hệ quả:** quan sát được lag/replication failure mà không làm sai read-after-write mặc định. Primary vẫn quyết định write availability; chưa có Patroni/DCS/fencing hoặc automatic promotion. Một Docker host là failure domain chung.

## ADR-012 — Debezium raw-table CDC song song với custom outbox

**Trạng thái:** đã áp dụng.

**Quyết định:** một Connect worker, bốn PostgreSQL connectors/slots/publications; snapshot initial, pgoutput, bảng chính REPLICA IDENTITY FULL. CDC topics tách domain topics; outbox/ledger loại khỏi capture. Init jobs tự tạo/verify; internal topics RF3 và compaction.

**Hệ quả:** thấy được c/u/d/r và full before image, đổi lại tăng WAL, CDC permissions, checkpoint/retention và schema coupling. Không chạy Debezium Outbox Router cùng publisher. Worker down không dừng business transaction, nhưng CDC lag tăng và phải bảo đảm WAL còn. PostgreSQL 16 logical-slot failover không được tự động hóa.

**Xem xét lại khi:** cần Connect worker HA, failover primary tự động, CDC throughput lớn, schema registry hoặc chuyển domain publishing sang Outbox Event Router có kế hoạch.

## ADR-014 — Warranty CDC là input nghiệp vụ của Inspection

A→B dùng REST cùng durable local provision command. C ghép vehicle domain event và warranty WAL CDC; cả hai gọi try_prepare_inspection, giữ advisory lock theo vehicle ID, ledger và projection cùng transaction. READY yêu cầu đủ hai phía; CDC source LSN bảo vệ replay/update/delete. Đánh đổi: tạo inspection mới phụ thuộc CDC availability; schema bảng warranty trở thành contract CDC cần migration cẩn thận.

## ADR-015 — Metrics tại nguồn, exporters theo runtime

Prometheus scrape ASGI/business/worker metrics và exporters thật. Grafana provision file, DNS discovery theo replica. Broker JMX bổ sung throughput/ISR; kafka-exporter đo offsets/lag; status exporter chỉ bổ sung Connect REST và Kafka assignment. cAdvisor đo Linux cgroups; không dùng process CPU hoặc số giả để thay container CPU. Cấu hình/kiểm chứng tại [Observability](OBSERVABILITY.md).

## ADR-016 — RabbitMQ + Celery cho biên bản kiểm định, Kafka giữ vai trò event stream

**Trạng thái:** đã áp dụng.

**Quyết định:** render biên bản kiểm định (PDF) là task Celery trên quorum queue `inspection.report.generate` của cụm RabbitMQ 3 node, không phải consumer Kafka và không chạy trong HTTP request. Dòng `inspection_reports` tạo trong transaction complete là ý định task; dispatcher publish với publisher confirm. Worker `acks_late`, prefetch 1, idempotent theo `inspection_id` tại commit point; retry qua Celery native delayed delivery, DLX/DLQ và `delivery-limit` là policy. Sự thật sau khi xong (`inspection.report.generated`) đi Kafka qua outbox; không message nào được gửi vào cả hai hệ thống.

**Hệ quả:** worker scale độc lập với số partition, task chậm không chặn event Kafka, retry/DLQ/priority dùng tính năng broker. Đổi lại thêm một cụm stateful (Raft cho queue và Khepri cho metadata), 28 quorum queue `celery_delayed_*` do Celery tạo, và một đường giao hàng at-least-once thứ hai cần idempotency riêng. Chi tiết: [Background Tasks](BACKGROUND_TASKS.md).

**Xem xét lại khi:** có nhiều loại task khác hồ sơ tài nguyên (tách queue/pool), cần workflow nhiều bước có trạng thái (orchestrator), hoặc tài liệu lớn cần object storage.
