# Priority topics

## P0 - MUST KNOW

P0 là nền tảng cần hiểu trước khi ghép một service: bài toán, ví dụ, ownership, cơ chế và failure. Các bài chính có diễn giải dài, diagram cùng cách đọc và code/lab cùng walkthrough. Các chuyên đề kế tiếp mở từng nhánh như netpoller, RWMutex hoặc Transport; đọc chúng khi cơ chế nền đã rõ, không dùng danh sách này thay nội dung bài.

- [Goroutine](../03-goroutines-scheduler/goroutine.md)
- [Go Scheduler / G-M-P](../03-goroutines-scheduler/scheduler-gmp.md)
- [Channels](../04-concurrency/channels.md)
- [Select](../04-concurrency/select.md)
- [Mutex](../04-concurrency/mutex.md)
- [Context](../05-context/context-basics.md)
- [Memory model](../02-memory-runtime/memory-model.md)
- [Stack vs Heap](../02-memory-runtime/stack-vs-heap.md)
- [Escape Analysis](../02-memory-runtime/escape-analysis.md)
- [Garbage Collector](../02-memory-runtime/garbage-collector.md)
- [Slices](../01-go-core/arrays-slices.md)
- [Maps](../01-go-core/maps.md)
- [Interfaces](../01-go-core/interfaces.md)
- [nil](../01-go-core/nil.md)
- [net/http](../06-http-backend/net-http.md)
- [HTTP client](../06-http-backend/http-client.md)
- [HTTP connection pooling](../06-http-backend/connection-pooling.md)
- [database/sql](../08-database/database-sql.md)
- [Database connection pool](../08-database/database-sql-pool.md)
- [Error handling](../01-go-core/errors.md)
- [Graceful shutdown](../06-http-backend/graceful-shutdown.md)
- [Race condition](../04-concurrency/race-condition.md)
- [Goroutine leak](../04-concurrency/goroutine-leak.md)
- [Worker pool](../04-concurrency/worker-pool.md)
- [pprof](../16-performance/pprof.md)
- [Distributed systems](../12-distributed-systems/fundamentals.md)
- [System Design](../13-system-design/system-design-framework.md)

## P1 - VERY IMPORTANT

- [gRPC](../07-api-design/grpc.md) và [Protobuf](../07-api-design/protobuf.md)
- [Kafka](../10-messaging/kafka.md) và [Redis](../09-redis-cache/redis-basics.md)
- [Clean Architecture](../11-software-architecture/clean-architecture.md) và [Microservices](../14-microservices/README.md)
- [Docker](../15-docker-kubernetes/docker-for-go.md), [Kubernetes](../15-docker-kubernetes/kubernetes.md)
- [Observability](../17-observability/README.md), [Testing](../18-testing/README.md)

## P2 - NICE TO KNOW

- [Advanced runtime internals](../02-memory-runtime/runtime-internals.md): đọc source tag đúng deployment.
- [Compiler details](../02-memory-runtime/escape-analysis.md): tối ưu sau khi có profile, không học private thresholds như luật.
- [Rare sync primitives](../04-concurrency/condition-variable.md): Cond/Once khi invariant cần.
- [Advanced generics](../01-go-core/generics.md): constraints/type sets, không thay mọi interface.

Chuyển từ P0 sang P1 khi có thể theo một ví dụ từ input tới output, chỉ ra ai sở hữu tài nguyên và điều gì xảy ra khi lỗi. P2 phục vụ nhu cầu cụ thể hoặc điều tra sâu; private runtime thresholds không cần học thuộc. Một buổi profile/test trong từng module giúp kiến thức gắn với hành vi thực.
