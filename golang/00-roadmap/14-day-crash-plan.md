# 14-day crash plan

Dành khoảng 3–4 giờ mỗi buổi cho nền tảng P0. Sau khi đọc bài, chạy ví dụ và mô tả từng bước dữ liệu/điểm chờ; không chuyển bài chỉ vì đã nhớ tên thuật ngữ. Đây là lịch tập trung, không cam kết người mới nắm toàn bộ runtime trong14 ngày.

Mỗi buổi nên có một ghi chép diễn tiến hoặc lab result cùng assumption. Nếu chưa giải thích được vì sao code block/unblock, dùng thêm thời gian cho cơ chế đó và giảm số chủ đề phụ. Các buổi phỏng vấn ở cuối là phụ lục tự chọn, có thể thay bằng việc review một service thực tế.

| Day | Focus | Exit task |
|---|---|---|
| 1 | [Core values, slices, maps](../01-go-core/arrays-slices.md) + [Interfaces, nil, method sets](../01-go-core/interfaces.md) | Vẽ aliasing trước/sau append; chạy ví dụ cap và clone. Giải thích typed nil và viết case error constructor success. |
| 2 | [Errors, defer, panic](../01-go-core/errors.md) + [Memory model](../02-memory-runtime/memory-model.md) | Wrap Is/As/Join và dự đoán defer outputs trước khi chạy. Vẽ happens-before cho publication, sửa race counter. |
| 3 | [Stack/heap và escape](../02-memory-runtime/escape-analysis.md) + [GC, allocation, retention](../02-memory-runtime/garbage-collector.md) | Đọc -m=2 với/không inline, phân biệt diagnostic và benchmem. So inuse_space/alloc_space và tính memory headroom. |
| 4 | [Goroutine và G-M-P](../03-goroutines-scheduler/scheduler-gmp.md) + [Scheduler/trace](../16-performance/trace.md) | Vẽ syscall return không P và network readiness paths. Thu trace worker cancellation, xác định runnable versus waiting. |
| 5 | [Channels/select](../04-concurrency/channels.md) + [Mutex/atomic/map](../04-concurrency/mutex.md) | Bảng nil/open/closed, giải thích cancel không priority. Nêu invariant nhiều fields; compare Mutex/RWMutex/sync.Map. |
| 6 | [Worker pool](../04-concurrency/worker-pool.md) + [Context/leak](../05-context/context-basics.md) | Chạy pool tests, bổ sung một cancellation timing case trong notes. Audit mọi blocking point trong pool và chứng minh join. |
| 7 | [HTTP request/server](../06-http-backend/net-http.md) + [Client/pools/timeouts](../06-http-backend/http-client.md) | Trace request flow và xác định lúc headers commit. Chạy TestFetch; giải thích new Client versus new Transport. |
| 8 | [Shutdown](../06-http-backend/graceful-shutdown.md) + [SQL/pools](../08-database/database-sql-pool.md) | Build server, SIGTERM smoke test, vẽ dependency close order. Giải500/20 và tổng pool ở max pods+surge. |
| 9 | [Transactions/query plans](../08-database/transactions.md) + [Redis/cache](../09-redis-cache/cache-stampede.md) | Vẽ crash/rollback paths; review isolation và N+1. Model hit 95%→0%, thiết kế bounded fallback. |
| 10 | [Kafka/order/dedup](../10-messaging/kafka.md) + [Distributed systems](../12-distributed-systems/fundamentals.md) | Vẽ DB commit→crash→offset replay và contiguous prefix. Giải timeout ambiguity, outbox và stale lease owner. |
| 11 | [Architecture/gRPC](../11-software-architecture/go-project-structure.md) + [Docker/Kubernetes](../15-docker-kubernetes/graceful-deployment.md) | Vẽ import/dependency direction và RPC deadline propagation. Giải CPU throttle, memory soft limit và termination budget. |
| 12 | [Performance/observability](../16-performance/pprof.md) + [Testing/security](../18-testing/README.md) | Chạy benchmark/profiles; chọn metric cho từng symptom. Race/fuzz labs; threat-model SSRF, IDOR và token validation. |
| 13 | [High-throughput design](../13-system-design/design-high-throughput-api.md) + [Migration design](../13-system-design/design-migration-platform.md) | 30 phút whiteboard20k RPS và cache outage arithmetic. Chứng minh snapshot+CDC không gap; verification/cutover. |
| 14 | [Production game day](../20-production-scenarios/README.md) + [Full mock + review](../23-mock-interview/full-mock-interview.md) | Ba incidents: high CPU,20k G,DB pool; nói first 10 minutes. 115 phút scored mock, fix 3 gaps và review cheatsheets. |

Ngày13 chọn high-throughput làm design chính, migration để học tiếp ordering/checkpoint. Ngày14 ưu tiên mock115 phút; nếu còn thời gian đọc [payment](../13-system-design/design-payment-system.md), luyện một coding bài và hai STAR stories trước [last-day review](../24-cheatsheets/last-day-review.md).
