# Full Mock Interview — 115 minutes

Interviewer giữ timebox; candidate hỏi assumptions, nói invariant và tự sửa khi có evidence. Score tổng100; mức tham khảo80+ với không có lỗi nghiêm trọng về correctness/cancellation. Đây là rubric luyện tập, không là hiring guarantee.

| Time | Section | Points |
|---|---|---:|
| 0–10 | Introduction | 5 |
| 10–30 | Go Core & Runtime | 20 |
| 30–50 | Concurrency | 20 |
| 50–65 | Backend / Database | 15 |
| 65–95 | System Design | 25 |
| 95–105 | Production Incident | 10 |
| 105–115 | Behavioral | 5 |

## 10 min — Introduction

**Describe a backend you owned and one constraint that shaped its design.**

Follow-up: **What did you personally change, and how did you verify the result?**

<details>
<summary>Answer</summary>

Cần context traffic/data/team scope, contribution cá nhân và một decision với alternatives. Evidence có thể là latency/errors/operational lead time thật; không bắt buộc số tuyệt đối nếu không nhớ, nhưng phải nói giới hạn. Chấm clarity và ownership, không thưởng buzzwords hoặc số liệu bịa.

</details>

## 20 min — Go Core & Runtime

**Explain why a tiny slice can retain a large allocation, then explain how that affects GC.**

**A goroutine enters a blocking syscall. What happens to G, M and P, and how would a socket wait differ?**

**Why can returning a nil pointer as error produce a non-nil result?**

<details>
<summary>Answer</summary>

Slice header giữ pointer vào backing array nên whole allocation reachable; clone phần cần giữ tách lifetime nhưng tăng copy/allocation. GC pressure phụ thuộc live set, allocation rate và pointer scan, không chỉ STW. G/M syscall có thể giữ OS thread trong kernel, P release/retake để M khác execute Go; khi return không có P thì G enqueue. Runtime-managed network FD park G qua netpoll, không giữ một dedicated M mỗi socket. Typed nil interface còn dynamic type nên interface!=nil; success phải return nil interface. Chấm8 memory,8 scheduler,4 nil; trừ mạnh nếu khẳng định return pointer luôn heap hoặc P là core vật lý.

</details>

## 20 min — Concurrency coding

**Implement a bounded worker pool that accepts context, stops on the first task error, and joins every worker before returning.**

Requirements: fixed positive worker count, caller owns jobs, fn honors context and does not panic. **What happens if the producer never closes input, or the caller cancels while workers are blocked?**

<details>
<summary>Answer</summary>

Xem [runnable pool](../examples/pool.go) và [tests](../examples/pool_test.go). Child context, fixed workers, Add trước launch, select ctx ở receive, cancel khi first error, buffered error slot không block, Wait trước return. Caller producer phải có cancellation riêng khi pool return sớm. Không claim pool có thể ép fn không hợp tác dừng. Chấm6 bounds/ownership,6 cancellation/error,4 join/cleanup,4 tests. Test job completion exactly once trong one run, cancel blocked workers, task error và active count zero sau return.

</details>

## 15 min — Backend / Database

**You have500 concurrent requests and sql.DB MaxOpenConns20. Latency is rising but database CPU is low. Diagnose it.**

**A team creates a new http.Client for each call. Under what circumstances does that actually destroy pooling?**

<details>
<summary>Answer</summary>

20 connections giới hạn holders; excess waits/cancel theo ctx. Tìm long Tx/Rows leak/dedicated Conn và DB lock waits; Stats InUse/Idle/Wait deltas rồi server sessions/locks, không tăng pool mù. Client mới với nil Transport vẫn shared DefaultTransport; Transport mới mỗi request mới phá reuse. Body phải Close, HTTP/1 thường cần EOF để reuse; bound read cho untrusted body. Chấm8 DB evidence/capacity,7 client nuance/lifecycle.

</details>

## 30 min — System Design

**Design a 20,000 RPS API with P99 below 200ms using Go, PostgreSQL, Redis, Kafka and Kubernetes.**

Clarify read/write ratio, cache hit, payload và durability. **What happens when Redis fails? How do retries and HPA affect your DB budget?**

<details>
<summary>Answer</summary>

Tham khảo [design đầy đủ](../13-system-design/design-high-throughput-api.md), gồm5 diagrams. Với90% reads/95% hit:900 read misses/s+2000 write ops/s nếu assumptions một operation một DB step. Mean50ms→1000 in-flight toàn fleet. Bound handlers/workers/pools; max replicas+surge nhân DB caps phải dưới verified server budget. Redis down đưa reads lên18k/s: bounded fallback/stale theo policy và shedding, không unrestricted fallback. Domain+outbox same Tx, idempotent consumer và commit contiguous offsets. Context remaining deadline, transport reuse, graceful drain, private pprof. Chấm5 requirements/estimates,5 data/API/commit,5 Go capacity,5 failures,5 observability/security/evolution. Không chấm target throughput là đạt nếu không có load-test gates.

</details>

## 10 min — Production Incident

**The service now has20,000 goroutines, low CPU and rising memory. What would you do in the first ten minutes?**

<details>
<summary>Answer</summary>

Assess user impact/traffic/connection count và recent deploy, cap intake nếu saturation. Capture goroutine groups và heap profile: chan send/receive, DB acquire, net waits hay mutex. Kiểm owner đã return, missing cancel/timeouts và queue bounds; low CPU gợi ý waiting chứ không chứng minh nguyên nhân. So G/heap sau drain; giữ evidence trước restart nếu không trì hoãn mitigation. Chấm4 evidence selection,3 bounded mitigation,3 regression/recovery verification.

</details>

## 10 min — Behavioral

**Tell me about a technical disagreement and an incident where you changed your approach after new evidence.**

<details>
<summary>Answer</summary>

Dùng facts cá nhân thật theo STAR. Nêu alternative công bằng, criteria và experiment; contribution của mình, cách communicate quyết định và outcome. Lesson cần action hệ thống có owner, không chỉ “cẩn thận hơn”. Chấm2 clarity,2 judgment/learning,1 team impact.

</details>

## Feedback form

- Ghi score từng section và một evidence cụ thể cho score.
- Chọn3 gaps lớn nhất; mỗi gap link tới bài liên quan trong [P0 roadmap](../00-roadmap/priority-topics.md).
- Làm một lab sửa gap và phỏng vấn lại sau48 giờ với inputs/failure timing khác.
- Red flags: unlimited goroutines/retries, ignored cleanup, timeout đồng nghĩa remote failure, exactly-once không nêu boundary, claims benchmark không có measurement.
