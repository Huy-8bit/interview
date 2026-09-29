# Senior Golang / Senior Backend Interview Preparation

Bộ tài liệu tiếng Việt, interview questions tiếng Anh cho Senior Golang, Senior Backend/Software Engineer, Platform và Distributed Systems Engineer. Học theo **WHAT → WHY → HOW → INTERNALS → RUNTIME → PRODUCTION → FAILURE → TRADE-OFF → DEBUGGING → INTERVIEW**.

## Learning Roadmap

- [30-day plan](00-roadmap/30-day-plan.md) —2–3 giờ/ngày, có deliverable cụ thể.
- [14-day crash plan](00-roadmap/14-day-crash-plan.md) —3–4 giờ/ngày, ưu tiên P0.
- [P0 / P1 / P2](00-roadmap/priority-topics.md) và [readiness checklist](00-roadmap/interview-checklist.md).

## Version và cách đọc

Mental model/spec contract đi trước implementation. Code labs baseline Go 1.23, kiểm chứng bằng toolchain **Go 1.26.4**; không gọi đây là phiên bản Go mới nhất. Map default Swiss Tables từ1.24; container-aware GOMAXPROCS từ1.25 tùy config; Green Tea GC mặc định1.26. Scheduler/GC/map private layouts có thể đổi: **Implementation detail, subject to change between Go releases.** Xem [sources/version policy](references.md).

27 bài canonical P0 được đánh dấu rõ; mỗi bài có30 câu theo10 basic/mid +10 senior +5 production +5 follow-ups. Các bài bổ trợ giải quyết từng chủ đề cụ thể và dẫn về deep dive. Snippets thiếu package/import được ghi rõ là snippet; code chạy được tập trung trong [examples](examples/README.md). Các estimates system design là giả định, không là benchmark đã đo.

## Module links và Progress tracker

Checkbox dành cho tiến độ học của bạn, không phải trạng thái tác giả viết tài liệu.

- [ ] [00-roadmap](00-roadmap/README.md) — Lập kế hoạch theo gap và role, có đầu ra hằng ngày.
- [ ] [01-go-core](01-go-core/README.md) — Giải thích semantics và ownership trước runtime.
- [ ] [02-memory-runtime](02-memory-runtime/README.md) — Liên hệ lifetime, allocation và GC với production memory.
- [ ] [03-goroutines-scheduler](03-goroutines-scheduler/README.md) — Theo dấu G/M/P qua CPU, syscall và network waits.
- [ ] [04-concurrency](04-concurrency/README.md) — Thiết kế synchronization và lifecycle có proof.
- [ ] [05-context](05-context/README.md) — Truyền budget/cancellation đúng request và service ownership.
- [ ] [06-http-backend](06-http-backend/README.md) — Bound HTTP resources, reuse pools và drain an toàn.
- [ ] [07-api-design](07-api-design/README.md) — Thiết kế API contracts, compatibility và trust boundaries.
- [ ] [08-database](08-database/README.md) — Giữ durable invariants và quản connection lifecycle.
- [ ] [09-redis-cache](09-redis-cache/README.md) — Cache là hệ consistency/failure có source capacity budget.
- [ ] [10-messaging](10-messaging/README.md) — Delivery, ordering, replay và backpressure trong Go consumers.
- [ ] [11-software-architecture](11-software-architecture/README.md) — Packages nhỏ, interfaces tại consumer, dependency direction rõ.
- [ ] [12-distributed-systems](12-distributed-systems/README.md) — Reason về safety/liveness/unknown outcomes và recovery.
- [ ] [13-system-design](13-system-design/README.md) — Whiteboard requirements→capacity→commit→failure→evolution.
- [ ] [14-microservices](14-microservices/README.md) — Vận hành network boundaries với version/deadline contracts.
- [ ] [15-docker-kubernetes](15-docker-kubernetes/README.md) — Nối Go runtime budgets với container/platform lifecycle.
- [ ] [16-performance](16-performance/README.md) — Tối ưu bằng profile và measurements đúng workload.
- [ ] [17-observability](17-observability/README.md) — Đo user impact và tìm evidence xuyên boundaries.
- [ ] [18-testing](18-testing/README.md) — Test invariants, protocol behavior và cancellation.
- [ ] [19-security](19-security/README.md) — Bảo vệ identity/resource/input và secrets boundaries.
- [ ] [20-production-scenarios](20-production-scenarios/README.md) — Tập incident response với giả thuyết có thể bác bỏ.
- [ ] [21-coding-interview](21-coding-interview/README.md) — Code đúng, giải thích complexity và edge cases.
- [ ] [22-behavioral](22-behavioral/README.md) — Nói về judgment/ownership bằng trải nghiệm thật.
- [ ] [23-mock-interview](23-mock-interview/README.md) — Phỏng vấn có timebox, đáp án và rubric.
- [ ] [24-cheatsheets](24-cheatsheets/README.md) — Ôn toàn bộ trong110 phút bằng compact prompts.

## Deep dive topics

- [G-M-P, syscalls, netpoll, preemption](03-goroutines-scheduler/scheduler-gmp.md)
- [Channel internals](04-concurrency/channels.md), [select](04-concurrency/select.md), [worker pool](04-concurrency/worker-pool.md)
- [Slices](01-go-core/arrays-slices.md), [interfaces/typed nil](01-go-core/interfaces.md), [maps/versioning](01-go-core/maps.md)
- [Memory model](02-memory-runtime/memory-model.md), [escape analysis](02-memory-runtime/escape-analysis.md), [GC](02-memory-runtime/garbage-collector.md)
- [HTTP pooling](06-http-backend/connection-pooling.md), [DB pooling](08-database/database-sql-pool.md), [graceful shutdown](06-http-backend/graceful-shutdown.md)

## System design labs

[API 20k RPS](13-system-design/design-high-throughput-api.md) · [Migration 4–5B records](13-system-design/design-migration-platform.md) · [Payments](13-system-design/design-payment-system.md) · [Gateway](13-system-design/design-api-gateway.md) · [Notifications](13-system-design/design-notification-system.md) · [Files](13-system-design/design-file-processing.md) · [Chat](13-system-design/design-chat-system.md) · [Jobs](13-system-design/design-job-processing-system.md) · [URL shortener](13-system-design/design-url-shortener.md).

Mỗi design có requirements, capacity/API/data model,5 diagrams, Go implementation, failures, observability, security, trade-offs và evolution.

## Production scenarios

[12 incident runbooks](20-production-scenarios/README.md): high latency/CPU/memory,20k goroutines, exhausted pools, slow DB, Redis down, Kafka lag, duplicates, traffic spike, races và outage. Mỗi bài gắn evidence với mitigation và recovery checks.

## Mock interviews và Cheatsheets

[115-minute full mock](23-mock-interview/full-mock-interview.md) · [Top 100 Go](23-mock-interview/top-100-golang-questions.md) · [Top 50 Backend](23-mock-interview/top-50-senior-backend-questions.md) · [110-minute last-day review](24-cheatsheets/last-day-review.md).

## Verification

[Runnable labs](examples/README.md) · [Repository audit](00-roadmap/repository-audit.md) · [Study-first lists](00-roadmap/study-first.md). Chỉ nội dung dưới `golang/` được tạo; Python được kiểm tra bằng content hashes.
