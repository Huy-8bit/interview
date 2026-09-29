# 30-day plan

Mỗi ngày2–3 giờ:45 phút đọc,45 phút code/diagram,30 phút trả lời English,15 phút ghi gaps. Ngày mock dành trọn115 phút rồi feedback.

| Day | Focus | Deliverable |
|---|---|---|
| 1 | [Core values, slices, maps](../01-go-core/arrays-slices.md) | Vẽ aliasing trước/sau append; chạy ví dụ cap và clone. |
| 2 | [Interfaces, nil, method sets](../01-go-core/interfaces.md) | Giải thích typed nil và viết case error constructor success. |
| 3 | [Errors, defer, panic](../01-go-core/errors.md) | Wrap Is/As/Join và dự đoán defer outputs trước khi chạy. |
| 4 | [Memory model](../02-memory-runtime/memory-model.md) | Vẽ happens-before cho publication, sửa race counter. |
| 5 | [Stack/heap và escape](../02-memory-runtime/escape-analysis.md) | Đọc -m=2 với/không inline, phân biệt diagnostic và benchmem. |
| 6 | [GC, allocation, retention](../02-memory-runtime/garbage-collector.md) | So inuse_space/alloc_space và tính memory headroom. |
| 7 | [Goroutine và G-M-P](../03-goroutines-scheduler/scheduler-gmp.md) | Vẽ syscall return không P và network readiness paths. |
| 8 | [Scheduler/trace](../16-performance/trace.md) | Thu trace worker cancellation, xác định runnable versus waiting. |
| 9 | [Channels/select](../04-concurrency/channels.md) | Bảng nil/open/closed, giải thích cancel không priority. |
| 10 | [Mutex/atomic/map](../04-concurrency/mutex.md) | Nêu invariant nhiều fields; compare Mutex/RWMutex/sync.Map. |
| 11 | [Worker pool](../04-concurrency/worker-pool.md) | Chạy pool tests, bổ sung một cancellation timing case trong notes. |
| 12 | [Context/leak](../05-context/context-basics.md) | Audit mọi blocking point trong pool và chứng minh join. |
| 13 | [HTTP request/server](../06-http-backend/net-http.md) | Trace request flow và xác định lúc headers commit. |
| 14 | [Client/pools/timeouts](../06-http-backend/http-client.md) | Chạy TestFetch; giải thích new Client versus new Transport. |
| 15 | [Shutdown](../06-http-backend/graceful-shutdown.md) | Build server, SIGTERM smoke test, vẽ dependency close order. |
| 16 | [SQL/pools](../08-database/database-sql-pool.md) | Giải500/20 và tổng pool ở max pods+surge. |
| 17 | [Transactions/query plans](../08-database/transactions.md) | Vẽ crash/rollback paths; review isolation và N+1. |
| 18 | [Redis/cache](../09-redis-cache/cache-stampede.md) | Model hit95%→0%, thiết kế bounded fallback. |
| 19 | [Kafka/order/dedup](../10-messaging/kafka.md) | Vẽ DB commit→crash→offset replay và contiguous prefix. |
| 20 | [Distributed systems](../12-distributed-systems/fundamentals.md) | Giải timeout ambiguity, outbox và stale lease owner. |
| 21 | [Architecture/gRPC](../11-software-architecture/go-project-structure.md) | Vẽ import/dependency direction và RPC deadline propagation. |
| 22 | [Docker/Kubernetes](../15-docker-kubernetes/graceful-deployment.md) | Giải CPU throttle, memory soft limit và termination budget. |
| 23 | [Performance/observability](../16-performance/pprof.md) | Chạy benchmark/profiles; chọn metric cho từng symptom. |
| 24 | [Testing/security](../18-testing/README.md) | Race/fuzz labs; threat-model SSRF, IDOR và token validation. |
| 25 | [High-throughput design](../13-system-design/design-high-throughput-api.md) | 30 phút whiteboard20k RPS và cache outage arithmetic. |
| 26 | [Migration design](../13-system-design/design-migration-platform.md) | Chứng minh snapshot+CDC không gap; verification/cutover. |
| 27 | [Payment + one design](../13-system-design/design-payment-system.md) | Unknown charge outcome và replay invariant; chọn chat/job/file. |
| 28 | [Production game day](../20-production-scenarios/README.md) | Ba incidents: high CPU,20k G,DB pool; nói first10 minutes. |
| 29 | [Coding + behavioral](../21-coding-interview/README.md) | Hai coding exercises và hai STAR stories thật có trade-off. |
| 30 | [Full mock + review](../23-mock-interview/full-mock-interview.md) | 115 phút scored mock, fix3 gaps và review cheatsheets. |

Nếu chưa giải thích được failure/debugging, dành buổi kế tiếp sửa gap trước chuyển P1. Giữ notes/lab artifacts trong `golang/` để không ảnh hưởng bộ ngôn ngữ khác.
