# Top 100 Golang Questions

Câu hỏi English, answer cues Vietnamese. Tự trả lời60–90 giây rồi mở đáp án; câu trả lời senior cần thêm trade-off và failure evidence.

## Core

### 1. Why can append mutate a caller's data?

<details>
<summary>Answer</summary>

Slice headers có thể chia backing array; append dùng lại array khi còn cap.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 2. Why can a tiny slice retain megabytes?

<details>
<summary>Answer</summary>

Pointer còn giữ whole backing allocation; clone để tách lifetime.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 3. Why is an interface containing a nil pointer non-nil?

<details>
<summary>Answer</summary>

Dynamic type vẫn tồn tại dù dynamic value là nil pointer.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 4. When can comparing interface values panic?

<details>
<summary>Answer</summary>

Dynamic value có type không comparable, ví dụ slice.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 5. Why can a value call a pointer method yet fail interface assignment?

<details>
<summary>Answer</summary>

Method-call addressability convenience khác method set của T.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 6. How does wrapping change error classification?

<details>
<summary>Answer</summary>

%w giữ cause để Is/As traverse; %v chỉ giữ text.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 7. How does errors.Join differ from a linear chain?

<details>
<summary>Answer</summary>

Nó tạo nhiều causes; Is/As hiểu tree, simple Unwrap assumption không đủ.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 8. When are defer arguments evaluated?

<details>
<summary>Answer</summary>

Khi đăng ký defer; closure đọc captured variable có thể thấy value lúc exit.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 9. Can recover in a parent catch a child goroutine panic?

<details>
<summary>Answer</summary>

Không, unwind/recover thuộc cùng goroutine.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 10. Why should map iteration not define an API signature?

<details>
<summary>Answer</summary>

Order không được guarantee; canonicalize bằng sorting/encoding contract.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>


## Memory

### 11. Does returning a pointer always allocate on the heap?

<details>
<summary>Answer</summary>

Không; inlining và escape tại final caller có thể đổi placement.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 12. How can a closure affect lifetime?

<details>
<summary>Answer</summary>

Closure được giữ lâu có thể giữ captured values reachable ngoài frame.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 13. Why is allocation rate different from live heap?

<details>
<summary>Answer</summary>

Churn đo objects mới, live heap đo reachable set sau GC.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 14. Why does low STW time not imply low GC cost?

<details>
<summary>Answer</summary>

Concurrent mark/assists vẫn tiêu CPU và tăng request latency.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 15. What does a write barrier protect?

<details>
<summary>Answer</summary>

GC reachability invariant khi pointers đổi, không phải user data synchronization.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 16. Why can GOMEMLIMIT fail to prevent OOM?

<details>
<summary>Answer</summary>

Nó soft và không bao toàn RSS/native memory; working set có thể quá lớn.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 17. What trade-off does increasing GOGC make?

<details>
<summary>Answer</summary>

Thường thêm heap headroom để giảm GC frequency, cần đo CPU và memory.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 18. Why can deleting map entries leave RSS high?

<details>
<summary>Answer</summary>

Backing capacity/allocator/OS release policy không thu nhỏ ngay.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 19. When can sync.Pool increase retained memory?

<details>
<summary>Answer</summary>

Buffer outlier lớn được reuse/giữ; cần cap size và đo live heap.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 20. Why is a GC-managed object not sufficient resource cleanup?

<details>
<summary>Answer</summary>

FD/rows/connections cần Close đúng lifetime thay chờ reachability collection.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>


## Runtime

### 21. Which runtime claims should be version-qualified?

<details>
<summary>Answer</summary>

Scheduler queue policy, map layout, GC implementation và allocator details.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 22. How did modern Go maps change from legacy buckets?

<details>
<summary>Answer</summary>

Go 1.24 default Swiss Tables; không dùng bucket/overflow model cũ như universal.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 23. What does Green Tea change at a high level?

<details>
<summary>Answer</summary>

GC scan scheduling/locality implementation; roots, reachability và pacing vẫn cần hiểu.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 24. Why does a goroutine's initial stack not describe its total cost?

<details>
<summary>Answer</summary>

Stack grow và G giữ heap references, runtime metadata cùng tài nguyên khác.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 25. Can stack growth invalidate ordinary Go pointers?

<details>
<summary>Answer</summary>

Runtime/compiler bảo đảm pointers hợp lệ; unsafe/uintptr cần contract riêng.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 26. Why can native memory be absent from a heap profile?

<details>
<summary>Answer</summary>

Go heap profile không là toàn process RSS/cgo/mmap accounting.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 27. What does compiler output leaking param actually mean?

<details>
<summary>Answer</summary>

Pointer flow/lifetime trong escape analysis, không tự là application memory leak.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 28. Why can a race-free program still be logically wrong?

<details>
<summary>Answer</summary>

Business read-check-write có thể thiếu atomicity qua operations/processes.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 29. What does goroutine exit publish automatically to a parent?

<details>
<summary>Answer</summary>

Không có join edge tự động; cần channel/WaitGroup theo contract.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 30. Why should private runtime layouts not be business dependencies?

<details>
<summary>Answer</summary>

Không stable ABI và có thể đổi giữa releases/architectures.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>


## Scheduler

### 31. How do G, M and P divide responsibilities?

<details>
<summary>Answer</summary>

G là execution context, M thread, P resource để chạy Go code.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 32. Does GOMAXPROCS cap OS threads?

<details>
<summary>Answer</summary>

Không; M có thể blocked syscall/cgo hoặc locked thread ngoài executing P.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 33. What happens to P during a blocking syscall?

<details>
<summary>Answer</summary>

Có thể release/retake để M khác chạy Go, không buộc chờ cùng M.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 34. How does network waiting differ from blocking disk I/O?

<details>
<summary>Answer</summary>

Runtime-managed nonblocking sockets park G qua netpoll; disk/cgo có thể giữ M.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 35. What happens when a syscall returns without an available P?

<details>
<summary>Answer</summary>

G có thể enqueue và M park thay chạy Go không có P.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 36. Why keep local run queues?

<details>
<summary>Answer</summary>

Giảm global contention và giữ locality; global queue hỗ trợ sharing/fairness.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 37. What can work stealing redistribute?

<details>
<summary>Answer</summary>

Runnable work giữa P, không sửa lock serialization hay hot business key.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 38. What does asynchronous preemption fail to guarantee?

<details>
<summary>Answer</summary>

Không có hard realtime latency hoặc business task fairness.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 39. Why can raising GOMAXPROCS worsen P99 in a container?

<details>
<summary>Answer</summary>

CPU quota throttle và lock/cache contention có thể tăng.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 40. How would you distinguish runnable delay from dependency wait?

<details>
<summary>Answer</summary>

Trace scheduler states kết hợp goroutine stacks và dependency spans.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>


## Concurrency

### 41. Does a buffered send confirm processing completed?

<details>
<summary>Answer</summary>

Không, chỉ handoff/enqueue; completion cần ack hoặc result protocol.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 42. What happens to receivers after a channel is closed?

<details>
<summary>Answer</summary>

Drain buffered values rồi zero,false; closed receive luôn ready.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 43. Why can select ignore cancellation for one iteration?

<details>
<summary>Answer</summary>

Jobs và Done cùng ready thì chọn pseudo-random, không priority.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 44. Who should close a channel shared by many producers?

<details>
<summary>Answer</summary>

Coordinator sau khi biết mọi producers đã dừng gửi.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 45. How can channel-based code still have a data race?

<details>
<summary>Answer</summary>

Gửi pointer/slice không deep-copy; sender/receiver cùng mutate object.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 46. Why can RLock followed by Lock deadlock?

<details>
<summary>Answer</summary>

RWMutex không hỗ trợ upgrade trong khi reader vẫn giữ lock.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 47. What invariant should a mutex protect?

<details>
<summary>Answer</summary>

Toàn read-check-write liên quan, không từng access rời rạc.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 48. Why does WaitGroup.Add belong before launching work?

<details>
<summary>Answer</summary>

Parent Wait không được thấy counter0 trước child đăng ký.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 49. Can a semaphore bound goroutines if acquired inside each child?

<details>
<summary>Answer</summary>

Không, children chờ permit vẫn có thể vô hạn; acquire trước launch.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 50. How do you prove a worker pool shuts down?

<details>
<summary>Answer</summary>

Mọi block có exit/cancel và owner join tất cả workers trước return.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>


## HTTP

### 51. Why should Transport be reused?

<details>
<summary>Answer</summary>

Nó giữ connection pool; new Transport tạo TCP/TLS/FD churn.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 52. Does a new http.Client always create a new pool?

<details>
<summary>Answer</summary>

Không; nil Transport dùng shared DefaultTransport.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 53. Why close response bodies after non-2xx responses?

<details>
<summary>Answer</summary>

Do success trao body ownership bất kể status; release resource vẫn bắt buộc.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 54. Why may closing a body not ensure HTTP/1 reuse?

<details>
<summary>Answer</summary>

Chưa đọc EOF có thể khiến connection không reuse được.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 55. Why not drain every body without limits?

<details>
<summary>Answer</summary>

Untrusted/infinite body có thể giữ memory/time; bound read rồi close.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 56. Does MaxIdleConnsPerHost limit active calls?

<details>
<summary>Answer</summary>

Không; idle cap khác total connection cap và H2 stream concurrency.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 57. Which phases does Client.Timeout cover?

<details>
<summary>Answer</summary>

Tổng request/redirect/body read; per-phase transport timeouts khác.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 58. Does WriteTimeout stop arbitrary handler computation?

<details>
<summary>Answer</summary>

Không; application code cần context/cooperative cancellation.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 59. What does Server.Shutdown not manage automatically?

<details>
<summary>Answer</summary>

Hijacked/WebSocket connections và arbitrary worker goroutines.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 60. Why use a fresh context after SIGTERM?

<details>
<summary>Answer</summary>

Signal context đã canceled sẽ làm Shutdown hết budget ngay.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>


## Database

### 61. What does sql.DB represent?

<details>
<summary>Answer</summary>

Long-lived concurrent-safe pool handle, không một connection.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 62. What happens with 500 requests and20 open connections?

<details>
<summary>Answer</summary>

Chỉ tối đa20 giữ slots, excess acquire waits/deadlines theo workload.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 63. How should WaitDuration be interpreted?

<details>
<summary>Answer</summary>

Cumulative counter; delta theo window và delta WaitCount cho waits observed.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 64. Why must Rows.Err be checked after iteration?

<details>
<summary>Answer</summary>

Next false có thể vì error chứ không chỉ EOF.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 65. Why can using db inside a transaction deadlock?

<details>
<summary>Answer</summary>

Tx giữ connection; db call cần connection khác khi pool đã đầy.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 66. Why avoid remote HTTP calls inside a transaction?

<details>
<summary>Answer</summary>

Kéo dài lock/connection hold và external call không nằm atomic DB boundary.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 67. Why can a timeout leave commit outcome unknown?

<details>
<summary>Answer</summary>

DB/provider có thể commit trước khi response bị mất.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 68. When does adding pool connections hurt?

<details>
<summary>Answer</summary>

Server CPU/IO/locks đã saturated, thêm concurrency tăng queue/contend.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 69. What changes when using pgxpool instead of pgx.Conn?

<details>
<summary>Answer</summary>

Pool quản concurrent acquire; single Conn có concurrency contract hẹp hơn.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 70. Why do generated SQL methods still need integration tests?

<details>
<summary>Answer</summary>

Schema, isolation, driver cancel và query plans là runtime behavior.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>


## Performance

### 71. Which profile answers where CPU time is spent?

<details>
<summary>Answer</summary>

CPU sampled stacks; inspect flat/cum/callers và quota metrics.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 72. Which profile distinguishes retained memory from churn?

<details>
<summary>Answer</summary>

Heap inuse_space so với alloc_space/alloc_objects.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 73. Why can summed contention exceed wall time?

<details>
<summary>Answer</summary>

Nhiều waiters cùng chờ được cộng vào cumulative contention.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 74. What does a goroutine snapshot fail to tell you alone?

<details>
<summary>Answer</summary>

Duration/progress/lifetime validity; cần repeated snapshots/timeline.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 75. When is execution trace preferable to aggregate profiles?

<details>
<summary>Answer</summary>

Cần scheduling delay, overlap và GC/network timeline.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 76. Why must benchmarks consume their outputs?

<details>
<summary>Answer</summary>

Compiler có thể loại dead computation; sink phải phù hợp lifetime thực.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 77. Why run multiple benchmark samples?

<details>
<summary>Answer</summary>

Tách noise khỏi effect; benchstat hỗ trợ statistical comparison.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 78. How can faster microbench code hurt production?

<details>
<summary>Answer</summary>

Retention, contention, payload distribution hoặc downstream bottleneck khác.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 79. Why should pprof endpoints be private?

<details>
<summary>Answer</summary>

Stack/runtime/request metadata và capture overhead cần controlled access.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 80. How would you validate an optimization?

<details>
<summary>Answer</summary>

Same offered load, correctness tests, P99/errors/throughput và resource metrics.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>


## Production

### 81. How would you investigate 20000 goroutines?

<details>
<summary>Answer</summary>

Trend sau drain, stack groups, owner/cancel paths và dependency waits.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 82. Why can stopping a ticker leave a goroutine blocked?

<details>
<summary>Answer</summary>

Stop không close C; range loop cần separate cancellation.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 83. Why can Redis failure overload PostgreSQL?

<details>
<summary>Answer</summary>

Cache misses tăng đột biến; bounded fallback/admission cần có sẵn.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 84. Why can HPA worsen pool exhaustion?

<details>
<summary>Answer</summary>

New replicas nhân total connections/demand lên cùng bottleneck.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 85. What follows DB success before Kafka offset commit?

<details>
<summary>Answer</summary>

Redelivery; dedup+effect transaction bảo vệ replay.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 86. Why can a consumer commit lose unfinished records?

<details>
<summary>Answer</summary>

Commit vượt hole khi parallel workers chưa hoàn tất earlier offsets.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 87. How should a rolling deploy protect accepted jobs?

<details>
<summary>Answer</summary>

Stop intake, drain/cancel+join, persist progress và idempotent replay.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 88. Why does normal RPS with 95% CPU need profiling?

<details>
<summary>Answer</summary>

Per-request work/loop/GC cost có thể tăng không đổi traffic.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 89. What proves incident recovery beyond health probes?

<details>
<summary>Answer</summary>

User SLIs, queues freshness và durable state reconciliation.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 90. Why is a retry storm a capacity problem?

<details>
<summary>Answer</summary>

Extra attempts tăng arrival trong lúc service rate giảm.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>


## Architecture

### 91. Why define interfaces near consumers?

<details>
<summary>Answer</summary>

Contract theo nhu cầu dùng, giảm coupling tới implementation/vendor API.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 92. When is accept interfaces, return structs inappropriate?

<details>
<summary>Answer</summary>

Public polymorphic abstraction có thể nên return interface; heuristic không là luật.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 93. Is pkg a required Go directory?

<details>
<summary>Answer</summary>

Không; convention optional, internal mới có toolchain visibility semantics.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 94. How can Clean Architecture become unidiomatic Go?

<details>
<summary>Answer</summary>

Layers/interfaces/class-like abstractions rỗng che control flow/transactions.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 95. When is a modular monolith preferable?

<details>
<summary>Answer</summary>

Boundaries có thể giữ trong process và chưa cần independent scale/deploy.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 96. What is the outbox solving?

<details>
<summary>Answer</summary>

Atomic domain state+event intent thay dual write DB/broker có crash window.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 97. Why is a distributed lease insufficient for correctness?

<details>
<summary>Answer</summary>

Old owner có thể tiếp tục; target cần fencing/version invariant.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 98. How do you choose sync versus async communication?

<details>
<summary>Answer</summary>

Product consistency, latency, durability và recovery contracts quyết định.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 99. Why must system design include Go pool budgets?

<details>
<summary>Answer</summary>

Runtime multiplexing không tạo unlimited downstream capacity.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 100. How would you evolve a 1k RPS backend toward 20k?

<details>
<summary>Answer</summary>

Measure bottleneck, bound resources, fix query/reuse/allocs, load-test và scale với aggregate budgets.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>
